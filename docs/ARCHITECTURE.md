# Architecture

This document explains the design rationale behind supermemory v2.

## The problem

Claude Code sessions are stateless. The transcripts persist as `.jsonl` files under `~/.claude/projects/`, but Claude itself does not read them across sessions. Three downstream pains:

1. **Re-explanation.** Every new session, the user re-pastes "what we did last time" or re-explains the project.
2. **Lost decisions.** Subtle decisions made in one session (why we chose A over B) never get distilled, never inform future sessions.
3. **Performance degradation as context grows.** The naive fix (`CLAUDE.md` stuffed with project history) inflates the eager load on every session, slowing Claude down.

The native features (`--resume`, built in recap) do not solve this. `--resume` reloads a full transcript at high token cost. The built in recap is an ephemeral one liner shown when the terminal goes idle.

## The principle

Three rules drive the design:

1. **Eager load minimum.** `SessionStart` should inject under 1 KB. Anything more is a tax on every future session.
2. **Lazy traversal always.** Past knowledge lives in a graph. Claude follows wikilinks on demand, reading only what is needed for the current question.
3. **Append only updates.** When new state lands (a session ends, a hub gets a new bullet), we append. We never re-read existing content to summarize it again. This is what keeps the system cheap at scale.

## The three pillars

### Pillar 1. Past sessions, auto summarized

Three hooks share a single shell script `on-summarize.sh`:

| Hook | Source value in JSON input | When it fires |
|---|---|---|
| `SessionEnd` | `SessionEnd` | Session terminates (clear, resume, logout, etc.) |
| `PreCompact` | `PreCompact` | Just before Claude Code compacts context |
| Slash command `/snapshot` | `manual` | User or Claude explicitly requests a checkpoint |

The hook script:

1. Reads JSON from stdin (Claude Code hook protocol).
2. Extracts `transcript_path`, `session_id`, `cwd`, `hook_event_name`.
3. Counts user turns. Skips if under 5 (trivial session).
4. Spawns a detached background `claude -p --model claude-haiku-4-5` process with the summarizer prompt and the transcript path passed as env.
5. Returns immediately (the hook is async true, so Claude Code does not block).

The headless Haiku process then writes four things:

1. **Raw extract** at `$VAULT/SuperMemory/YYYY-MM-DD_<slug>_raw.md`. Verbatim user and assistant turns. Tool calls collapsed to one line headers. Large tool outputs stripped.
2. **Beautified summary** at `$VAULT/SuperMemory/YYYY-MM-DD_<slug>.md`. Structured per `templates/session.md`. Frontmatter, what happened, decisions, files changed, errors, key context for next session, connections.
3. **Index update.** One line appended to `$VAULT/SuperMemory/Index.md` under today's `## YYYY-MM-DD` heading.
4. **Hub updates.** For each entity mentioned in the session (project, person, ticket, concept), one bullet appended to its hub page in `Projects/`, `People/`, `Work/Tickets/`, or `Concepts/`. If the hub does not exist, the summarizer creates a stub from the matching template.

#### The append only invariant

This is the most important rule. The summarizer:

* Never reads `Index.md` content (only checks existence and appends).
* Never reads existing hub content (only appends to the `## Recent sessions` section).
* Never reads other session files.
* Only reads the current session's `.jsonl` transcript.

This prevents the summarizer's input from growing as the vault grows. At session 1000, the summarizer reads the same volume of input as at session 1.

### Pillar 2. Live cross session visibility

Problem: a user runs Claude in three tmux panes for different parts of a monorepo. The three sessions are blind to each other. If pane 1 is editing a file, pane 2 has no way to know.

Solution: a tiny status registry at `~/.claude/sessions/<session_id>.json` per active session. Schema:

```json
{
  "session_id": "abc123",
  "cwd": "/Users/me/repo/apps/web",
  "started_at": "2026-05-24T20:00:00Z",
  "last_active": "2026-05-24T20:42:13Z",
  "last_prompt": "fix the calendar bug",
  "topic": "calendar tombstone tweak",
  "active_files": ["apps/web/src/stores/bookings-store.ts"]
}
```

Maintained by four cheap bash hooks (no Claude calls, sub millisecond):

| Hook | What it does |
|---|---|
| `SessionStart` | Creates the JSON file, sweeps stale files (over 4 hours of inactivity) |
| `UserPromptSubmit` | Updates `last_prompt` (truncated 200 chars), bumps `last_active` |
| `PreToolUse(Edit\|Write)` | Adds the edited file path to `active_files` (dedupe, keep last 5) |
| `SessionEnd` | Removes the JSON file |

Two read paths:

1. **`SessionStart` injection.** The hook includes a one line summary of each peer session in `additionalContext`. So the new Claude knows about its peers automatically.
2. **`/peers` slash command.** Manual deep dive. Lists each peer with cwd, last_active, last_prompt, active_files.

Atomic writes via `lockf` (macOS) or `flock` (Linux). Multiple sessions cannot corrupt each other's files.

### Pillar 3. Minimum eager load on SessionStart

`on-session-start.sh` outputs `additionalContext` with three components:

1. **Last 2 sessions.** `grep` the top of `Index.md` for `^- \[\[`, take the first two.
2. **cwd matching hub.** Walk `Projects/*.md`, find one whose `directory:` frontmatter is a prefix of the current `cwd`. Take that hub's one line summary.
3. **Active peers.** List of other sessions with their cwd basename and topic.

Plus a breadcrumb telling Claude to lazy load via wikilinks rather than pre fetching.

Typical injection size: 500 to 650 bytes. The previous approach (paste full recent history) was 5 to 10 KB per session.

## The graph

Wikilinks `[[Page Name]]` connect everything. Hub pages aggregate sessions. Sessions link back to hubs. Hub pages link to related hubs. The graph is dense by construction.

Two enforcement mechanisms:

1. **The summarizer prompt** forbids cross vault links. Every `[[link]]` must resolve to a file inside the vault. No links to `~/.claude/...` paths.
2. **`lint.sh`** detects dead wikilinks, orphan pages (no inbound links), and stale hubs (no session reference in 30 days). Run periodically to keep the graph clean.

## Token budget

For a typical user with about 100 past sessions in the vault:

| Operation | Token cost |
|---|---|
| `SessionStart` injection | ~500 bytes, roughly 150 tokens |
| Reading a specific session file via wikilink | 2 to 5 KB, roughly 600 to 1500 tokens |
| Reading a hub page | 1 to 3 KB, roughly 300 to 900 tokens |
| Summarizer (background, Haiku) | 5 to 20 KB input, 2 to 5 KB output, $0.005 to $0.02 |

Compare to the baseline (no supermemory):

| Operation | Token cost |
|---|---|
| Paste "what we did last time" | 5 to 20 KB, roughly 1500 to 6000 tokens, every session |
| Reload a past transcript via `--resume` | 50 to 500 KB |

## Failure modes

* **`claude` CLI missing.** Summarizer skips. Hooks log and continue. No session impact.
* **`jq` missing.** Install warns and exits. (Required dependency.)
* **Vault path wrong or unwritable.** Hook logs error. Session continues normally.
* **Lock file contention.** `lockf` and `flock` have 5 second timeouts. If they fail, the append is dropped (logged), session continues.
* **Background Haiku call hangs or fails.** Detached with `nohup`, so it cannot block the session. Errors land in `$VAULT/.logs/YYYYMMDD-summarizer.log`.
* **Stale peer files from crashed sessions.** `SessionStart` sweeps files older than 4 hours.

## What is intentionally not implemented

* **Stop hook (every assistant turn).** Too chatty. Adds significant overhead for marginal gain.
* **Auto pruning.** Only `rotate.sh` (manual archival) and `lint.sh` (suggests, does not delete) modify the vault structure.
* **Multi vault sync.** This is a single user, single machine tool. If you want cloud sync, use Obsidian Sync or a git remote on the vault.
* **A web UI.** Obsidian is the UI.

## Why this design over alternatives

| Alternative | Why we did not pick it |
|---|---|
| Embed everything in `~/.claude/CLAUDE.md` | Eager load grows with every project |
| Single global memory file | Same problem, plus no graph |
| Vector DB sidecar | Overkill; markdown grep plus wikilinks works fine at this scale |
| `--resume` past transcripts | High token cost per resume |
| Pure native recap | Ephemeral, not persisted, single line |

## Future work (not in v2)

* Embedding based retrieval inside the vault for "find sessions about X" without keyword grep.
* Auto detection of when Claude itself should call `/snapshot` mid session.
* Optional integration with an external memex service.
