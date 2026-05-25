#!/usr/bin/env bash
# SuperMemory v2 -- PreToolUse(Edit|Write) hook
# Tracks files this session is editing for peer visibility.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=$(echo "$INPUT" | sm_jq_field '.session_id')
FILE_PATH=$(echo "$INPUT" | sm_jq_field '.tool_input.file_path')

[ -z "$SESSION_ID" ] && exit 0
[ -z "$FILE_PATH" ] && exit 0

sm_peer_add_file "$SESSION_ID" "$FILE_PATH"

exit 0
