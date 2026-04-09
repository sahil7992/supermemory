# SuperMemory

Automatic logging of every Claude Code interaction to your Obsidian vault. Every prompt, tool call, agent spawn, and response — captured with zero manual effort.

## What it does

SuperMemory uses Claude Code hooks to intercept every event in your sessions and write structured, wiki-linked markdown notes to your Obsidian vault:

- **Session logs** — chronological timeline of every interaction in a conversation
- **Agent notes** — atomic notes for each agent spawn with prompt and result
- **Error notes** — auto-detected errors get their own linked note
- **Auto-updated index** — MOC linking all sessions, sortable by date

### Example session log

```markdown
# Session — 2026-04-09 14:30

> **Session ID**: `abc123` | **Directory**: `/Users/me/project`

## Summary
_Session in `/Users/me/project` | 47 events | Duration: 23m 15s_

## Timeline

### 14:30:03 — User Prompt
> Build the authentication system

- `14:30:04` **Read** — src/auth.ts
<details><summary>Result: Read — import express from...</summary>...</details>

- `14:30:06` **Agent** — Research auth patterns
  - See [[2026-04-09_14-30-06_Agent_Research_auth_patterns]]

---
## Session End
> **Duration**: 23m 15s | **Events**: 47
```

## Requirements

- [Claude Code](https://claude.ai/claude-code) CLI
- [Obsidian](https://obsidian.md) (any version)
- `jq` — JSON processor
- `lockf` (macOS) or `flock` (Linux) — for atomic file writes

## Installation

```bash
git clone https://github.com/sahil7992/supermemory.git
cd supermemory
bash install.sh
```

**Custom vault path:**

```bash
bash install.sh "/path/to/your/vault/SuperMemory"
```

Then add to your `~/.zshrc` or `~/.bashrc`:

```bash
export SUPERMEMORY_VAULT_DIR="/path/to/your/vault/SuperMemory"
```

**Restart Claude Code** after installation (hooks load at session start).

## Uninstallation

```bash
bash uninstall.sh
```

This removes hooks but keeps your Obsidian notes.

## How it works

Six Claude Code hooks route to a single dispatcher script:

| Hook Event | What it captures |
|---|---|
| `SessionStart` | Creates session log, initializes state |
| `UserPromptSubmit` | Every user prompt |
| `PreToolUse` | Every tool call (Read, Write, Bash, Agent, etc.) |
| `PostToolUse` | Every tool result, including errors |
| `Stop` | Session end, duration, event count |
| `SubagentStop` | Agent completion with results |

### Architecture

```
Hook Event → stdin JSON → dispatcher.sh → parse with jq → append to Obsidian .md
```

- Single dispatcher script handles all events (~15-25ms per invocation)
- Session state tracked in `/tmp/supermemory_<session_id>`
- Atomic writes via `lockf`/`flock` for concurrent safety
- Scripts never return exit code 2 (which would block Claude)

### Obsidian structure

```
SuperMemory/
├── Index.md          # Keyword → topic lookup (grep target, 100 line cap)
├── Topics/           # Distilled knowledge (30 line cap per file)
│   ├── DMS-Debugging.md
│   ├── QuickSight-Reports.md
│   └── ...
├── Sessions/         # Raw session logs (auto-captured by hooks)
├── Agents/           # One .md per agent spawn
├── Errors/           # Auto-detected errors
└── Archive/          # Sessions older than 30 days (via rotate.sh)
```

### Two-tier memory

1. **Raw layer** (automatic via hooks) — every event captured in `Sessions/`
2. **Knowledge layer** (maintained by Claude at session end) — distilled facts in `Topics/`

Retrieval cost: 1 grep on Index.md + 1 read of a topic file = **~800 tokens**. Not thousands.

### Session rotation

```bash
bash rotate.sh                    # Archive sessions older than 30 days
bash rotate.sh /path/to/vault 60  # Custom path and days
```

All notes use `[[wiki links]]` for Obsidian graph connectivity.

## Manual configuration

If you prefer to configure hooks manually, add this to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SessionStart"}
    ],
    "UserPromptSubmit": [
      {"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh UserPromptSubmit"}
    ],
    "PreToolUse": [
      {"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PreToolUse"}]}
    ],
    "PostToolUse": [
      {"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PostToolUse"}]}
    ],
    "Stop": [
      {"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh Stop"}
    ],
    "SubagentStop": [
      {"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SubagentStop"}
    ]
  }
}
```

## License

MIT
