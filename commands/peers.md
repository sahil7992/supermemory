---
description: Show what other running Claude sessions are doing right now
allowed-tools: Bash
---

Listing active Claude sessions other than this one.

!SELF="${CLAUDE_SESSION_ID:-}"; for f in ~/.claude/sessions/*.json; do [ -f "$f" ] || continue; sid=$(basename "$f" .json); [ "$sid" = "$SELF" ] && continue; jq -r '"━━━ \(.session_id[0:8]) ━━━\n  cwd:          \(.cwd)\n  started:      \(.started_at)\n  last_active:  \(.last_active)\n  last_prompt:  \(.last_prompt)\n  topic:        \(.topic)\n  active_files: \(.active_files | join(\", \"))"' "$f" 2>/dev/null; done; [ -z "$(ls ~/.claude/sessions/*.json 2>/dev/null | grep -v "${SELF}.json")" ] && echo "No other active sessions."
