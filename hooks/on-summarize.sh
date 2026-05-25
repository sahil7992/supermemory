#!/usr/bin/env bash
# SuperMemory v2 — summarization hook
# Used by: SessionEnd, PreCompact, /recap slash command.
# Reads hook JSON on stdin, spawns headless Haiku in background, returns immediately.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

INPUT="$(cat 2>/dev/null || true)"

TRANSCRIPT=$(echo "$INPUT" | sm_jq_field '.transcript_path')
SESSION_ID=$(echo "$INPUT" | sm_jq_field '.session_id')
CWD=$(echo "$INPUT" | sm_jq_field '.cwd')
TRIGGER=$(echo "$INPUT" | sm_jq_field '.hook_event_name')
TRIGGER="${TRIGGER:-manual}"

sm_log "summarize: trigger=$TRIGGER session=$SESSION_ID cwd=$CWD transcript=$TRANSCRIPT"

# Sanity: need a real transcript path.
if [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then
  sm_log "summarize: no readable transcript, skipping"
  exit 0
fi

# Skip trivial sessions.
TURNS=$(sm_user_turn_count "$TRANSCRIPT")
TURNS=${TURNS:-0}
if [ "$TURNS" -lt 5 ]; then
  sm_log "summarize: only $TURNS user turns, skipping"
  exit 0
fi

# Skip if no claude CLI.
if ! command -v claude >/dev/null 2>&1; then
  sm_log "summarize: claude CLI not found in PATH, skipping"
  exit 0
fi

PROMPT_FILE="$SM_PROMPT"
if [ ! -r "$PROMPT_FILE" ]; then
  sm_log "summarize: prompt file $PROMPT_FILE not readable, skipping"
  exit 0
fi

# Build the prompt with substituted env. Read the template, prepend env context.
PROMPT_TEXT=$(cat <<EOF
TRANSCRIPT_PATH=$TRANSCRIPT
VAULT=$SM_VAULT
TRIGGER=$TRIGGER
SESSION_ID=$SESSION_ID
CWD=$CWD

$(cat "$PROMPT_FILE")
EOF
)

# Spawn detached headless Haiku. Don't block the hook.
(
  nohup claude -p "$PROMPT_TEXT" \
    --model claude-haiku-4-5 \
    --output-format text \
    >> "$SM_LOGS/$(date +%Y%m%d)-summarizer.log" 2>&1 &
  disown 2>/dev/null || true
)

sm_log "summarize: spawned headless summarizer (turns=$TURNS)"
exit 0
