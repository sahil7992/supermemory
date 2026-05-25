---
description: Snapshot the current session to SuperMemory now (mid-session checkpoint)
allowed-tools: Bash
---

Snapshotting current session to SuperMemory.

!echo "{\"transcript_path\": \"${CLAUDE_TRANSCRIPT_PATH:-}\", \"session_id\": \"${CLAUDE_SESSION_ID:-}\", \"cwd\": \"${CLAUDE_PROJECT_DIR:-$PWD}\", \"hook_event_name\": \"manual\"}" | ~/.claude/hooks/supermemory/on-summarize.sh && echo "Recap dispatched. Tail ~/Documents/Obsidian\ Vault/.logs/$(date +%Y%m%d)-summarizer.log to follow."
