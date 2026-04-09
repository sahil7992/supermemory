#!/usr/bin/env bash
# SuperMemory dispatcher — routes Claude Code hook events to handlers
# Logs every interaction to Obsidian vault as structured markdown
# https://github.com/sahil7992/supermemory
set -uo pipefail

# CRITICAL: Never block Claude. Exit 0 on any error.
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Bail if vault parent doesn't exist
VAULT_PARENT="${SM_VAULT_DIR%/*}"
VAULT_ROOT="${VAULT_PARENT%/*}"
[ -d "$VAULT_ROOT" ] || exit 0

EVENT="${1:-}"
[ -z "$EVENT" ] && exit 0

PAYLOAD=$(cat)

SESSION_ID=$(echo "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

sm_ensure_dirs

# ============================================================
# Late init — for hooks firing before/without SessionStart
# ============================================================
sm_late_init() {
  local cwd
  cwd=$(echo "$PAYLOAD" | jq -r '.cwd // "(unknown)"' 2>/dev/null)

  local file_dt session_id_short session_filename session_filepath
  file_dt=$(sm_file_datetime)
  session_id_short="${SESSION_ID:0:8}"
  session_filename="${file_dt}_${session_id_short}"
  session_filepath="$SM_VAULT_DIR/Sessions/${session_filename}.md"

  cat > "$session_filepath" << HEADER
# Session — $(date "+%Y-%m-%d %H:%M")

> **Session ID**: \`${SESSION_ID}\` | **Directory**: \`${cwd}\`
> _Resumed session (no SessionStart captured)_

## Summary
_Auto-generated session. Summary populated at session end._

## Timeline

HEADER

  sm_write_state "$SESSION_ID" \
    "SESSION_FILE=$session_filepath" \
    "SESSION_NAME=$session_filename" \
    "START_TIME=$(date +%s)" \
    "EVENT_COUNT=0" \
    "CWD=$cwd" \
    "LAST_AGENT_NOTE="

  . "$(sm_state_file "$SESSION_ID")"
}

# ============================================================
# Handler: SessionStart
# ============================================================
handle_SessionStart() {
  local cwd
  cwd=$(echo "$PAYLOAD" | jq -r '.cwd // "(unknown)"' 2>/dev/null)

  local file_dt session_id_short session_filename session_filepath
  file_dt=$(sm_file_datetime)
  session_id_short="${SESSION_ID:0:8}"
  session_filename="${file_dt}_${session_id_short}"
  session_filepath="$SM_VAULT_DIR/Sessions/${session_filename}.md"

  cat > "$session_filepath" << HEADER
# Session — $(date "+%Y-%m-%d %H:%M")

> **Session ID**: \`${SESSION_ID}\` | **Directory**: \`${cwd}\`

## Summary
_Auto-generated session. Summary populated at session end._

## Timeline

HEADER

  sm_write_state "$SESSION_ID" \
    "SESSION_FILE=$session_filepath" \
    "SESSION_NAME=$session_filename" \
    "START_TIME=$(date +%s)" \
    "EVENT_COUNT=0" \
    "CWD=$cwd" \
    "LAST_AGENT_NOTE="

  # Append to Index
  local index_file="$SM_VAULT_DIR/Index.md"
  if [ ! -f "$index_file" ]; then
    cat > "$index_file" << 'IDX'
# SuperMemory Index

> Auto-updated map of all Claude Code sessions logged to Obsidian.

## Recent Sessions

IDX
  fi

  sm_safe_append "$index_file" "- [[${session_filename}]] — \`${cwd}\` | started $(date '+%H:%M')" "$SESSION_ID"
}

# ============================================================
# Handler: UserPromptSubmit
# ============================================================
handle_UserPromptSubmit() {
  sm_read_state "$SESSION_ID" || sm_late_init

  local user_prompt
  user_prompt=$(echo "$PAYLOAD" | jq -r '.user_prompt // "(empty prompt)"' 2>/dev/null)
  user_prompt=$(sm_truncate "$user_prompt" 2000)

  local ts
  ts=$(sm_timestamp)

  local quoted
  quoted=$(sm_blockquote "$user_prompt")

  local entry="
### ${ts} — User Prompt
${quoted}
"

  sm_safe_append "$SESSION_FILE" "$entry" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"
}

# ============================================================
# Handler: PreToolUse
# ============================================================
handle_PreToolUse() {
  sm_read_state "$SESSION_ID" || sm_late_init

  local tool_name tool_input summary
  tool_name=$(echo "$PAYLOAD" | jq -r '.tool_name // "(unknown)"' 2>/dev/null)
  if echo "$PAYLOAD" | jq -e '.tool_input | type == "object"' &>/dev/null; then
    tool_input=$(echo "$PAYLOAD" | jq -c '.tool_input' 2>/dev/null)
  else
    tool_input=$(echo "$PAYLOAD" | jq -r '.tool_input // "{}"' 2>/dev/null)
  fi

  summary=$(sm_tool_summary "$tool_name" "$tool_input")

  local ts
  ts=$(sm_timestamp)

  local entry="- \`${ts}\` **${tool_name}** — ${summary}"

  sm_safe_append "$SESSION_FILE" "$entry" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"

  # Create atomic agent note for Agent spawns
  if [ "$tool_name" = "Agent" ]; then
    local agent_desc agent_note_name agent_note_path
    agent_desc=$(echo "$tool_input" | jq -r '.description // "unnamed"' 2>/dev/null)
    agent_note_name="$(date '+%Y-%m-%d_%H-%M-%S')_Agent_$(echo "$agent_desc" | tr ' /:' '_--' | tr -cd '[:alnum:]_-' | head -c 40)"
    agent_note_path="$SM_VAULT_DIR/Agents/${agent_note_name}.md"

    local agent_prompt agent_type
    agent_prompt=$(sm_truncate "$(echo "$tool_input" | jq -r '.prompt // "(no prompt)"' 2>/dev/null)" 3000)
    agent_type=$(echo "$tool_input" | jq -r '.subagent_type // "general-purpose"' 2>/dev/null)

    cat > "$agent_note_path" << AGENT
# Agent — ${agent_desc}

> **Session**: [[${SESSION_NAME}]]
> **Time**: ${ts}
> **Type**: ${agent_type}

## Prompt
${agent_prompt}

## Result
_Pending — will be populated on completion._
AGENT

    local state_file
    state_file="$(sm_state_file "$SESSION_ID")"
    sed -i '' "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE='$agent_note_path'|" "$state_file" 2>/dev/null || \
      sed -i "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE='$agent_note_path'|" "$state_file"

    sm_safe_append "$SESSION_FILE" "  - See [[${agent_note_name}]]" "$SESSION_ID"
  fi
}

# ============================================================
# Handler: PostToolUse
# ============================================================
handle_PostToolUse() {
  sm_read_state "$SESSION_ID" || sm_late_init

  local tool_name tool_result
  tool_name=$(echo "$PAYLOAD" | jq -r '.tool_name // "(unknown)"' 2>/dev/null)
  if echo "$PAYLOAD" | jq -e '.tool_result | type == "object"' &>/dev/null; then
    tool_result=$(echo "$PAYLOAD" | jq -c '.tool_result' 2>/dev/null)
  else
    tool_result=$(echo "$PAYLOAD" | jq -r '.tool_result // "(no result)"' 2>/dev/null)
  fi

  local truncated_result first_line
  truncated_result=$(sm_truncate "$tool_result" 2000)
  first_line=$(echo "$truncated_result" | head -1 | head -c 80)

  local entry="<details>
<summary>Result: ${tool_name} — ${first_line}</summary>

\`\`\`
${truncated_result}
\`\`\`

</details>"

  sm_safe_append "$SESSION_FILE" "$entry" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"

  # Populate pending agent note
  if [ -n "${LAST_AGENT_NOTE:-}" ] && [ -f "${LAST_AGENT_NOTE:-}" ] && [ "$tool_name" = "Agent" ]; then
    local agent_result escaped_result
    agent_result=$(sm_truncate "$tool_result" 3000)
    escaped_result=$(echo "$agent_result" | head -20 | sed 's/[&/\]/\\&/g' | tr '\n' ' ')
    sed -i '' "s|_Pending — will be populated on completion._|${escaped_result}|" "$LAST_AGENT_NOTE" 2>/dev/null || \
      sed -i "s|_Pending — will be populated on completion._|${escaped_result}|" "$LAST_AGENT_NOTE" 2>/dev/null || true

    local state_file
    state_file="$(sm_state_file "$SESSION_ID")"
    sed -i '' "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE=''|" "$state_file" 2>/dev/null || \
      sed -i "s|^LAST_AGENT_NOTE=.*|LAST_AGENT_NOTE=''|" "$state_file"
  fi

  # Create error note for substantial errors
  if [ "${#tool_result}" -gt 100 ]; then
    if echo "$tool_result" | grep -qiE '(error|FAILED|exception|traceback|panic|fatal)'; then
      local error_note_name error_note_path
      error_note_name="$(date '+%Y-%m-%d_%H-%M-%S')_error_${tool_name}"
      error_note_path="$SM_VAULT_DIR/Errors/${error_note_name}.md"

      local tool_input_str
      if echo "$PAYLOAD" | jq -e '.tool_input | type == "object"' &>/dev/null; then
        tool_input_str=$(echo "$PAYLOAD" | jq -c '.tool_input' 2>/dev/null)
      else
        tool_input_str=$(echo "$PAYLOAD" | jq -r '.tool_input // "{}"' 2>/dev/null)
      fi

      cat > "$error_note_path" << ERROR
# Error — ${tool_name}

> **Session**: [[${SESSION_NAME}]]
> **Time**: $(sm_timestamp)
> **Tool**: ${tool_name}

## Context
\`\`\`
$(sm_truncate "$tool_input_str" 1000)
\`\`\`

## Error
\`\`\`
$(sm_truncate "$tool_result" 2000)
\`\`\`
ERROR

      sm_safe_append "$SESSION_FILE" "  - **Error detected** — See [[${error_note_name}]]" "$SESSION_ID"
    fi
  fi
}

# ============================================================
# Handler: Stop
# ============================================================
handle_Stop() {
  sm_read_state "$SESSION_ID" || return 0

  local now end_time duration_secs duration_min duration_sec
  now=$(date +%s)
  end_time=$(sm_datetime)
  duration_secs=$((now - START_TIME))
  duration_min=$((duration_secs / 60))
  duration_sec=$((duration_secs % 60))

  local entry="
---

## Session End
> **Ended**: ${end_time}
> **Duration**: ${duration_min}m ${duration_sec}s
> **Events logged**: ${EVENT_COUNT}"

  sm_safe_append "$SESSION_FILE" "$entry" "$SESSION_ID"

  # Update summary placeholder (macOS sed, then Linux sed fallback)
  sed -i '' "s|_Auto-generated session. Summary populated at session end._|_Session in \`${CWD}\` \| ${EVENT_COUNT} events \| Duration: ${duration_min}m ${duration_sec}s_|" "$SESSION_FILE" 2>/dev/null || \
    sed -i "s|_Auto-generated session. Summary populated at session end._|_Session in \`${CWD}\` \| ${EVENT_COUNT} events \| Duration: ${duration_min}m ${duration_sec}s_|" "$SESSION_FILE"

  # Update Index.md with duration
  local index_file="$SM_VAULT_DIR/Index.md"
  sed -i '' "s|\(.*\[\[${SESSION_NAME}\]\].*\)|\1 \| ${duration_min}m ${duration_sec}s|" "$index_file" 2>/dev/null || \
    sed -i "s|\(.*\[\[${SESSION_NAME}\]\].*\)|\1 \| ${duration_min}m ${duration_sec}s|" "$index_file"

  # Cleanup state
  rm -f "$(sm_state_file "$SESSION_ID")" "$(sm_lock_file "$SESSION_ID")"
}

# ============================================================
# Handler: SubagentStop
# ============================================================
handle_SubagentStop() {
  sm_read_state "$SESSION_ID" || return 0

  local tool_result
  if echo "$PAYLOAD" | jq -e '.tool_result | type == "object"' &>/dev/null; then
    tool_result=$(echo "$PAYLOAD" | jq -c '.tool_result' 2>/dev/null)
  else
    tool_result=$(echo "$PAYLOAD" | jq -r '.tool_result // "(no result)"' 2>/dev/null)
  fi

  local truncated first_line ts
  truncated=$(sm_truncate "$tool_result" 2000)
  first_line=$(echo "$truncated" | head -1 | head -c 80)
  ts=$(sm_timestamp)

  local entry="
### ${ts} — Subagent Completed

<details>
<summary>${first_line}</summary>

\`\`\`
${truncated}
\`\`\`

</details>"

  sm_safe_append "$SESSION_FILE" "$entry" "$SESSION_ID"
  sm_update_state_counter "$SESSION_ID"
}

# ============================================================
# Route to handler
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
