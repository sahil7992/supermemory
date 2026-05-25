#!/usr/bin/env bash
# SuperMemory -- UserPromptSubmit hook
# Updates peer registry with last_prompt and bumps last_active. Cheap; no claude calls.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=$(echo "$INPUT" | sm_jq_field '.session_id')
PROMPT=$(echo "$INPUT" | sm_jq_field '.prompt')

[ -z "$SESSION_ID" ] && exit 0

# Truncate prompt to 200 chars, strip newlines.
PROMPT_SHORT=$(echo "$PROMPT" | tr '\n' ' ' | cut -c1-200 | sed "s/'/\\\\'/g")

sm_peer_update "$SESSION_ID" "last_prompt" "$PROMPT_SHORT"

exit 0
