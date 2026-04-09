#!/usr/bin/env bash
# SuperMemory dispatcher v3 — optimized for speed + lightweight logs
# https://github.com/sahil7992/supermemory
set -uo pipefail
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

VAULT_PARENT="${SM_VAULT_DIR%/*}"
[ -d "${VAULT_PARENT%/*}" ] || exit 0

EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0

PAYLOAD=$(cat)

# Single jq call to extract all common fields at once
eval "$(echo "$PAYLOAD" | jq -r '
  "P_SESSION_ID=\(.session_id // "")",
  "P_CWD=\(.cwd // "(unknown)")",
  "P_TOOL_NAME=\(.tool_name // "")",
  "P_USER_PROMPT=\(.user_prompt // "")"
' 2>/dev/null | sed "s/'/'\\''/g; s/=\(.*\)/='\1'/")"

[ -z "$P_SESSION_ID" ] && exit 0
SESSION_ID="$P_SESSION_ID"

sm_ensure_dirs

# Read-only tools — skip result details for these (just noise)
is_readonly_tool() {
  case "$1" in
    Read|Grep|Glob|ToolSearch|TaskGet|TaskList|ListMcpResourcesTool|ReadMcpResourceTool) return 0 ;;
    *) return 1 ;;
  esac
}

# ============================================================
sm_late_init() {
  local file_dt session_id_short session_filename session_filepath
  file_dt=$(sm_file_datetime)
  session_id_short="${SESSION_ID:0:8}"
  session_filename="${file_dt}_${session_id_short}"
  session_filepath="$SM_VAULT_DIR/Sessions/${session_filename}.md"

  cat > "$session_filepath" << HEADER
# Session — $(date "+%Y-%m-%d %H:%M")

> **Session ID**: \`${SESSION_ID}\` | **Directory**: \`${P_CWD}\`
> _Resumed session_

## Summary
_Auto-generated. Updated at session end._

## Timeline

HEADER

  sm_write_state "$SESSION_ID" \
    "SESSION_FILE=$session_filepath" \
    "SESSION_NAME=$session_filename" \
    "START_TIME=$(date +%s)" \
    "EVENT_COUNT=0" \
    "CWD=$P_CWD" \
    "LAST_AGENT_NOTE="
  . "$(sm_state_file "$SESSION_ID")"
}

# ============================================================
handle_SessionStart() {
  local file_dt session_id_short session_filename session_filepath
  file_dt=$(sm_file_datetime)
  session_id_short="${SESSION_ID:0:8}"
  session_filename="${file_dt}_${session_id_short}"
  session_filepath="$SM_VAULT_DIR/Sessions/${session_filename}.md"

  cat > "$session_filepath" << HEADER
# Session — $(date "+%Y-%m-%d %H:%M")

> **Session ID**: \`${SESSION_ID}\` | **Directory**: \`${P_CWD}\`

## Summary
_Auto-generated. Updated at session end._

## Timeline

HEADER

  sm_write_state "$SESSION_ID" \
    "SESSION_FILE=$session_filepath" \
    "SESSION_NAME=$session_filename" \
    "START_TIME=$(date +%s)" \
    "EVENT_COUNT=0" \
    "CWD=$P_CWD" \
    "LAST_AGENT_NOTE="

  # Append to Index (cap at 10)
  local index_file="$SM_VAULT_DIR/Index.md"
  [ ! -f "$index_file" ] && printf '# SuperMemory Index\n\n## Recent Sessions\n\n' > "$index_file"
  sm_safe_append "$index_file" "- [[${session_filename}]] — \`${P_CWD}\` | $(date '+%H:%M')" "$SESSION_ID"

  local total
  total=$(grep -c '^- \[\[' "$index_file" 2>/dev/null || echo 0)
  if [ "$total" -gt 10 ]; then
    local start_line
    start_line=$(grep -n '## Recent Sessions' "$index_file" | head -1 | cut -d: -f1)
    [ -n "$start_line" ] && {
      local excess=$((total - 10))
      local first=$((start_line + 2))
      sed -i '' "${first},$((first + excess - 1))d" "$index_file" 2>/dev/null || \
        sed -i "${first},$((first + excess - 1))d" "$index_file"
    }
  fi
}

# ============================================================
handle_UserPromptSubmit() {
  sm_read_state "$SESSION_ID" || sm_late_init
  local ts=$(sm_timestamp)
  local prompt=$(sm_truncate "$P_USER_PROMPT" 2000)

  sm_safe_append "$SESSION_FILE" "
### ${ts} — User Prompt
$(sm_blockquote "$prompt")
" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"
}

# ============================================================
handle_PreToolUse() {
  sm_read_state "$SESSION_ID" || sm_late_init

  local tool_input
  if echo "$PAYLOAD" | jq -e '.tool_input | type == "object"' &>/dev/null; then
    tool_input=$(echo "$PAYLOAD" | jq -c '.tool_input' 2>/dev/null)
  else
    tool_input=$(echo "$PAYLOAD" | jq -r '.tool_input // "{}"' 2>/dev/null)
  fi

  local summary=$(sm_tool_summary "$P_TOOL_NAME" "$tool_input")
  local ts=$(sm_timestamp)

  sm_safe_append "$SESSION_FILE" "- \`${ts}\` **${P_TOOL_NAME}** — ${summary}" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"

  # Agent spawn → atomic note
  if [ "$P_TOOL_NAME" = "Agent" ]; then
    local agent_desc=$(echo "$tool_input" | jq -r '.description // "unnamed"' 2>/dev/null)
    local agent_note_name="$(date '+%Y-%m-%d_%H-%M-%S')_Agent_$(echo "$agent_desc" | tr ' /:' '_--' | tr -cd '[:alnum:]_-' | head -c 40)"
    local agent_note_path="$SM_VAULT_DIR/Agents/${agent_note_name}.md"

    cat > "$agent_note_path" << AGENT
# Agent — ${agent_desc}

> **Session**: [[${SESSION_NAME}]] | **Time**: ${ts} | **Type**: $(echo "$tool_input" | jq -r '.subagent_type // "general"' 2>/dev/null)

## Prompt
$(sm_truncate "$(echo "$tool_input" | jq -r '.prompt // "(no prompt)"' 2>/dev/null)" 3000)

## Result
_Pending_
AGENT

    local state_file="$(sm_state_file "$SESSION_ID")"
    sed -i '' "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE='$agent_note_path'|" "$state_file" 2>/dev/null || \
      sed -i "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE='$agent_note_path'|" "$state_file"
    sm_safe_append "$SESSION_FILE" "  - See [[${agent_note_name}]]" "$SESSION_ID"
  fi
}

# ============================================================
handle_PostToolUse() {
  sm_read_state "$SESSION_ID" || sm_late_init

  local tool_result
  if echo "$PAYLOAD" | jq -e '.tool_result | type == "object"' &>/dev/null; then
    tool_result=$(echo "$PAYLOAD" | jq -c '.tool_result' 2>/dev/null)
  else
    tool_result=$(echo "$PAYLOAD" | jq -r '.tool_result // "(no result)"' 2>/dev/null)
  fi

  # OPTIMIZATION: Skip result details for read-only tools (Read, Grep, Glob etc.)
  # These are exploration noise — PreToolUse already logged WHAT was read
  if ! is_readonly_tool "$P_TOOL_NAME"; then
    local truncated=$(sm_truncate "$tool_result" 2000)
    local first_line=$(echo "$truncated" | head -1 | head -c 80)

    sm_safe_append "$SESSION_FILE" "<details>
<summary>Result: ${P_TOOL_NAME} — ${first_line}</summary>

\`\`\`
${truncated}
\`\`\`

</details>" "$SESSION_ID"
  fi

  sm_update_state_counter "$SESSION_ID"

  # Populate agent note
  if [ -n "${LAST_AGENT_NOTE:-}" ] && [ -f "${LAST_AGENT_NOTE:-}" ] && [ "$P_TOOL_NAME" = "Agent" ]; then
    local escaped=$(sm_truncate "$tool_result" 3000 | head -20 | sed 's/[&/\]/\\&/g' | tr '\n' ' ')
    sed -i '' "s|_Pending_|${escaped}|" "$LAST_AGENT_NOTE" 2>/dev/null || \
      sed -i "s|_Pending_|${escaped}|" "$LAST_AGENT_NOTE" 2>/dev/null || true
    local state_file="$(sm_state_file "$SESSION_ID")"
    sed -i '' "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE=''|" "$state_file" 2>/dev/null || \
      sed -i "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE=''|" "$state_file"
  fi

  # Error detection — only for mutating tools (skip read-only false positives)
  if ! is_readonly_tool "$P_TOOL_NAME" && [ "${#tool_result}" -gt 100 ]; then
    if echo "$tool_result" | grep -qiE '(error|FAILED|exception|traceback|panic|fatal)'; then
      local error_note_name="$(date '+%Y-%m-%d_%H-%M-%S')_error_${P_TOOL_NAME}"
      local error_note_path="$SM_VAULT_DIR/Errors/${error_note_name}.md"

      local tool_input_str
      if echo "$PAYLOAD" | jq -e '.tool_input | type == "object"' &>/dev/null; then
        tool_input_str=$(echo "$PAYLOAD" | jq -c '.tool_input' 2>/dev/null)
      else
        tool_input_str=$(echo "$PAYLOAD" | jq -r '.tool_input // "{}"' 2>/dev/null)
      fi

      cat > "$error_note_path" << ERROR
# Error — ${P_TOOL_NAME}

> **Session**: [[${SESSION_NAME}]] | **Time**: $(sm_timestamp)

## Context
\`\`\`
$(sm_truncate "$tool_input_str" 1000)
\`\`\`

## Error
\`\`\`
$(sm_truncate "$tool_result" 2000)
\`\`\`
ERROR
      sm_safe_append "$SESSION_FILE" "  - **Error** — See [[${error_note_name}]]" "$SESSION_ID"
    fi
  fi
}

# ============================================================
handle_Stop() {
  sm_read_state "$SESSION_ID" || return 0

  local now=$(date +%s)
  local dur=$((now - START_TIME))
  local m=$((dur / 60)) s=$((dur % 60))

  sm_safe_append "$SESSION_FILE" "
---
## Session End
> **Ended**: $(sm_datetime) | **Duration**: ${m}m ${s}s | **Events**: ${EVENT_COUNT}" "$SESSION_ID"

  sed -i '' "s|_Auto-generated. Updated at session end._|_\`${CWD}\` \| ${EVENT_COUNT} events \| ${m}m ${s}s_|" "$SESSION_FILE" 2>/dev/null || \
    sed -i "s|_Auto-generated. Updated at session end._|_\`${CWD}\` \| ${EVENT_COUNT} events \| ${m}m ${s}s_|" "$SESSION_FILE"

  local index_file="$SM_VAULT_DIR/Index.md"
  sed -i '' "s|\(.*\[\[${SESSION_NAME}\]\].*\)|\1 \| ${m}m ${s}s|" "$index_file" 2>/dev/null || \
    sed -i "s|\(.*\[\[${SESSION_NAME}\]\].*\)|\1 \| ${m}m ${s}s|" "$index_file"

  rm -f "$(sm_state_file "$SESSION_ID")" "$(sm_lock_file "$SESSION_ID")"
}

# ============================================================
handle_SubagentStop() {
  sm_read_state "$SESSION_ID" || return 0

  local tool_result
  if echo "$PAYLOAD" | jq -e '.tool_result | type == "object"' &>/dev/null; then
    tool_result=$(echo "$PAYLOAD" | jq -c '.tool_result' 2>/dev/null)
  else
    tool_result=$(echo "$PAYLOAD" | jq -r '.tool_result // "(no result)"' 2>/dev/null)
  fi

  local truncated=$(sm_truncate "$tool_result" 2000)
  local ts=$(sm_timestamp)

  sm_safe_append "$SESSION_FILE" "
### ${ts} — Subagent Completed
$(echo "$truncated" | head -3)
" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"
}

# ============================================================
case "$EVENT" in
  SessionStart)     handle_SessionStart ;;
  UserPromptSubmit) handle_UserPromptSubmit ;;
  PreToolUse)       handle_PreToolUse ;;
  PostToolUse)      handle_PostToolUse ;;
  Stop)             handle_Stop ;;
  SubagentStop)     handle_SubagentStop ;;
  *)                exit 0 ;;
esac
exit 0
