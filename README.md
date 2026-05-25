# SuperMemory v2

> Persistent, lazy-loaded knowledge graph for Claude Code sessions. Auto-writes session summaries to Obsidian; injects ~500 bytes of breadcrumbs at session start; lets parallel Claude sessions see each other in real time.

**Status:** v2 (this branch). v1 (the noisy hook-spam approach) is preserved at the `v1-archive` tag and deprecated.

## What v2 does

Three pillars:

### 1. Past sessions → auto-summarized into a graph

After every session (`SessionEnd`), before any context compaction (`PreCompact`), and on-demand (`/recap`), a headless `claude -p` call with **Haiku 4.5** reads the just-finished `.jsonl` transcript and writes:

- `SuperMemory/YYYY-MM-DD_<slug>_raw.md` — verbatim turn dump
- `SuperMemory/YYYY-MM-DD_<slug>.md` — structured summary (what happened, decisions, files changed, next-session context)
- One line appended to `SuperMemory/Index.md`
- One bullet appended to each entity hub mentioned (`Projects/X.md`, `People/Y.md`, etc.)

**Invariant:** the summarizer is append-only. It never reads prior wiki/SuperMemory content. This is the token discipline that keeps the system from blowing up as the vault grows.

### 2. Live cross-session visibility → peers registry

Each running session writes a tiny `~/.claude/sessions/<id>.json` (cwd, last prompt, files being edited). Any Claude can call **`/peers`** to see what its peers are doing in other tmux panes — invaluable when running parallel agents or just multiple `claude` invocations.

### 3. Minimal eager-load

`SessionStart` injects only ~500-650 bytes of `additionalContext`: last 2 session one-liners + the project hub matching your `cwd` + active peer summaries. Claude is taught to **lazy-load** — grep `Index.md`, follow wikilinks on demand. No more pasting "what we did last time" into prompts.

## Vault structure

```
~/Documents/Obsidian Vault/
├── Home.md
├── index.md           — wiki catalog
├── log.md             — chronological ops log
├── SuperMemory/       — session chronicle (Index.md + per-session files)
├── Projects/          — hub pages (e.g. KaalSync, Curantis AI)
├── People/            — hub pages (e.g. Sahil Pambhar, Rakesh)
├── Concepts/          — domain concepts
├── Work/Tickets/      — per-ticket hubs
├── Playbooks/         — step-by-step guides
├── Feedback/          — behavior corrections
├── Templates/         — page templates (Haiku reads these)
└── Archive/           — sessions rotated out (>30 days)
```

## Requirements

- [Claude Code](https://www.anthropic.com/claude-code) CLI (`claude` on PATH)
- [Obsidian](https://obsidian.md) for browsing — not strictly required, but the graph view is the payoff
- `jq` (`brew install jq` / `apt install jq`)
- `lockf` (macOS) or `flock` (Linux) — for atomic writes (optional but recommended)

## Install

```bash
git clone https://github.com/sahil7992/supermemory.git
cd supermemory
bash install.sh
```

Custom vault path:
```bash
bash install.sh "/path/to/your/Obsidian Vault"
```

Then add to `~/.zshrc`:
```bash
export SUPERMEMORY_VAULT_DIR="/path/to/your/Obsidian Vault"
```

**Restart Claude Code** so hooks load.

## First-run revival (recommended)

If you've been using Claude Code without SuperMemory:

```bash
bash scripts/revive-wiki.sh    # scaffolds hub pages from existing ~/.claude memory
bash scripts/backfill.sh       # auto-summarizes recent .jsonl transcripts into SuperMemory
```

## Slash commands

| Command | What it does |
|---|---|
| `/recap` | Snapshot current session to SuperMemory immediately (mid-session checkpoint) |
| `/peers` | Show what other running Claude sessions are doing right now |

## Hooks installed

| Event | Hook | Purpose |
|---|---|---|
| `SessionStart` | `on-session-start.sh` | Inject breadcrumbs + register self in peer registry |
| `UserPromptSubmit` | `on-prompt.sh` | Update peer registry with last prompt |
| `PreToolUse(Edit\|Write)` | `on-edit.sh` | Track files being edited for peer visibility |
| `PreCompact` | `on-summarize.sh` | Snapshot before context compaction |
| `SessionEnd` | `on-session-end.sh` | Remove peer entry + trigger final summarization |

Everything runs `async: true` — hooks return immediately, background spawns Haiku.

## Maintenance

```bash
bash scripts/lint.sh      # Dead wikilinks, orphan pages, stale hubs
bash scripts/rotate.sh    # Move sessions >30 days into Archive/
bash scripts/backfill.sh  # Catch up after long offline period
```

## Uninstall

```bash
bash uninstall.sh
```

Removes hooks + slash commands + strips entries from `settings.json`. Your vault content stays untouched.

## How v2 differs from v1

| | v1 (deprecated) | v2 |
|---|---|---|
| Hooks | 6 hooks logging every event | 5 hooks, only 2 do meaningful work |
| Output | Verbatim event dump | Curated summary + raw extract |
| Cost | Bash-only, but very chatty | Bash for peers (cheap) + Haiku for summaries (~pennies per session) |
| Eager load on SessionStart | Nothing | ~500 bytes of targeted breadcrumbs |
| Wiki | Promised "Topics/" never built | Hubs auto-maintained across `Projects/`, `People/`, etc. |
| Cross-session visibility | None | `/peers` and SessionStart injection |
| Graph navigability | Often dangling | Append-only invariant + lint script |

## License

MIT
