#!/usr/bin/env bash
# SuperMemory v2 - summarization hook
# Used by: SessionEnd, PreCompact, /recap slash command.
# Strategy: pre-extract the .jsonl into a markdown raw dump (so headless Claude
# can read it without needing access to ~/.claude/projects/), then spawn
# headless Haiku to write the beautified summary + Index/hub appends.

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

# Sanity: need a real transcript.
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

# --- Pre-extract: convert .jsonl into a readable markdown dump ---------------
# We write the raw extract directly to the vault (it IS the _raw.md output).
# The headless summarizer reads it from /tmp instead of the original .jsonl.

EXTRACT_DIR="/tmp/supermemory-extracts"
mkdir -p "$EXTRACT_DIR"
EXTRACT="$EXTRACT_DIR/sm-extract-$SESSION_ID.md"

DATE_TAG=$(date +%Y-%m-%d)

# jq filter: turn each user/assistant/tool_use line into a readable section.
jq -r --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg trig "$TRIGGER" '
  if (.type == "user" and (.message.content | type) == "string"
      and (.message.content | startswith("<") | not)
      and (.message.content | length > 0)) then
    "## [" + (.timestamp[11:16]) + "] user\n" + .message.content + "\n"

  elif (.type == "user" and (.message.content | type) == "array") then
    (.message.content | map(select(.type == "tool_result") | "- tool_result (" + (.tool_use_id // "?")[0:8] + ")") | join("\n")) as $tr
    | if ($tr | length) > 0 then "## [" + (.timestamp[11:16]) + "] user (tool results)\n" + $tr + "\n" else empty end

  elif .type == "assistant" then
    "## [" + (.timestamp[11:16]) + "] assistant\n" +
    (.message.content | map(
      if .type == "text" then .text
      elif .type == "tool_use" then
        "- " + .name + ": " + (
          if .input.file_path then .input.file_path
          elif .input.command then (.input.command | tostring | .[0:120])
          elif .input.pattern then (.input.pattern | tostring)
          elif .input.path then .input.path
          elif .input.url then .input.url
          elif .input.query then (.input.query | tostring | .[0:120])
          elif .input.description then (.input.description | tostring | .[0:80])
          else (.input | keys | join(","))
          end
        )
      else empty end
    ) | join("\n")) + "\n"

  else empty
  end
' "$TRANSCRIPT" > "$EXTRACT" 2>/dev/null || true

if [ ! -s "$EXTRACT" ]; then
  sm_log "summarize: extract is empty, skipping"
  exit 0
fi

# Prepend frontmatter to the extract file.
TMP_EXTRACT=$(mktemp)
{
  echo "---"
  echo "type: raw"
  echo "date: $DATE_TAG"
  echo "session_id: $SESSION_ID"
  echo "cwd: $CWD"
  echo "trigger: $TRIGGER"
  echo "---"
  echo ""
  echo "# Raw extract: $SESSION_ID"
  echo ""
  cat "$EXTRACT"
} > "$TMP_EXTRACT" && mv "$TMP_EXTRACT" "$EXTRACT"

sm_log "summarize: extract written ($(wc -c < "$EXTRACT") bytes) at $EXTRACT"

# --- Spawn headless Haiku ----------------------------------------------------
# Pass the extract path (in /tmp, which is in the default sandbox) and add-dir
# the vault so the writer can land files there.

PROMPT_TEXT=$(cat <<EOF
EXTRACT_PATH=$EXTRACT
VAULT=$SM_VAULT
TRIGGER=$TRIGGER
SESSION_ID=$SESSION_ID
CWD=$CWD
DATE=$DATE_TAG

$(cat "$PROMPT_FILE")
EOF
)

(
  nohup claude -p "$PROMPT_TEXT" \
    --model claude-haiku-4-5 \
    --output-format text \
    --permission-mode bypassPermissions \
    --allowedTools "Read,Write,Edit,Glob,LS,Bash" \
    --add-dir "$EXTRACT_DIR" \
    --add-dir "$SM_VAULT" \
    >> "$SM_LOGS/$(date +%Y%m%d)-summarizer.log" 2>&1 &
  disown 2>/dev/null || true
)

sm_log "summarize: spawned headless summarizer (turns=$TURNS, extract=$EXTRACT)"
exit 0
