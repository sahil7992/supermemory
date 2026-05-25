#!/usr/bin/env bash
# SuperMemory v2 -- SessionEnd hook
# Removes peer registry entry, then triggers summarization.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=$(echo "$INPUT" | sm_jq_field '.session_id')

[ -n "$SESSION_ID" ] && sm_peer_remove "$SESSION_ID"

# Re-feed the input to on-summarize so it can spawn Haiku.
echo "$INPUT" | "$SCRIPT_DIR/on-summarize.sh"

exit 0
