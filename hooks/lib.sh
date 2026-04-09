#!/usr/bin/env bash
# SuperMemory shared library — fast utility functions for hook scripts
# https://github.com/sahil7992/supermemory

# Default vault path — override with SUPERMEMORY_VAULT_DIR env var
SM_VAULT_DIR="${SUPERMEMORY_VAULT_DIR:-$HOME/Documents/Obsidian Vault/SuperMemory}"

sm_ensure_dirs() {
  mkdir -p "$SM_VAULT_DIR/Sessions" "$SM_VAULT_DIR/Agents" "$SM_VAULT_DIR/Errors"
}

sm_state_file() {
  echo "/tmp/supermemory_${1}"
}

sm_lock_file() {
  echo "/tmp/supermemory_${1}.lock"
}

sm_timestamp() {
  date "+%H:%M:%S"
}

sm_datestamp() {
  date "+%Y-%m-%d"
}

sm_datetime() {
  date "+%Y-%m-%d %H:%M:%S"
}

sm_file_datetime() {
  date "+%Y-%m-%d_%H-%M"
}

sm_truncate() {
  local max="${2:-2000}"
  local text="$1"
  if [ "${#text}" -gt "$max" ]; then
    echo "${text:0:$max}... [truncated]"
  else
    echo "$text"
  fi
}

sm_safe_append() {
  # Atomic append via lockf (macOS) or flock (Linux)
  local file="$1"
  local content="$2"
  local lock_file
  lock_file="$(sm_lock_file "${3:-default}")"
  if command -v lockf &>/dev/null; then
    lockf -t 5 "$lock_file" bash -c "printf '%s\n' \"\$1\" >> \"\$2\"" _ "$content" "$file"
  elif command -v flock &>/dev/null; then
    flock -w 5 "$lock_file" bash -c "printf '%s\n' \"\$1\" >> \"\$2\"" _ "$content" "$file"
  else
    printf '%s\n' "$content" >> "$file"
  fi
}

sm_read_state() {
  local state_file
  state_file="$(sm_state_file "$1")"
  if [ -f "$state_file" ]; then
    . "$state_file"
    return 0
  fi
  return 1
}

sm_write_state() {
  # Values are single-quoted to handle spaces in paths (e.g., "Obsidian Vault")
  local state_file
  state_file="$(sm_state_file "$1")"
  shift
  for kv in "$@"; do
    local key="${kv%%=*}"
    local val="${kv#*=}"
    echo "${key}='${val}'"
  done > "$state_file"
}

sm_update_state_counter() {
  local state_file
  state_file="$(sm_state_file "$1")"
  if [ -f "$state_file" ]; then
    local count
    count=$(grep '^EVENT_COUNT=' "$state_file" | sed "s/^EVENT_COUNT='//" | sed "s/'$//")
    count=$((count + 1))
    sed -i '' "s/^EVENT_COUNT=.*/EVENT_COUNT='$count'/" "$state_file" 2>/dev/null || \
      sed -i "s/^EVENT_COUNT=.*/EVENT_COUNT='$count'/" "$state_file"
  fi
}

sm_blockquote() {
  echo "$1" | sed 's/^/> /'
}

sm_tool_summary() {
  local tool="$1"
  local input="$2"
  case "$tool" in
    Read|Write|Edit)
      echo "$input" | jq -r '.file_path // "(unknown)"' 2>/dev/null
      ;;
    Bash)
      local cmd
      cmd=$(echo "$input" | jq -r '.command // "(unknown)"' 2>/dev/null)
      sm_truncate "$cmd" 200
      ;;
    Grep)
      local pattern path
      pattern=$(echo "$input" | jq -r '.pattern // ""' 2>/dev/null)
      path=$(echo "$input" | jq -r '.path // "."' 2>/dev/null)
      echo "/$pattern/ in $path"
      ;;
    Glob)
      echo "$input" | jq -r '.pattern // "(unknown)"' 2>/dev/null
      ;;
    Agent)
      echo "$input" | jq -r '.description // "(unknown)"' 2>/dev/null
      ;;
    WebSearch)
      echo "$input" | jq -r '.query // "(unknown)"' 2>/dev/null
      ;;
    WebFetch)
      echo "$input" | jq -r '.url // "(unknown)"' 2>/dev/null
      ;;
    TaskCreate|TaskUpdate)
      echo "$input" | jq -r '.subject // .taskId // "(task op)"' 2>/dev/null
      ;;
    SendMessage)
      local to
      to=$(echo "$input" | jq -r '.to // "?"' 2>/dev/null)
      echo "to: $to"
      ;;
    Skill)
      echo "$input" | jq -r '.skill // "(unknown)"' 2>/dev/null
      ;;
    *)
      local summary
      summary=$(echo "$input" | jq -r 'tostring' 2>/dev/null | head -c 200)
      [ -z "$summary" ] && summary="(unknown)"
      echo "$summary"
      ;;
  esac
}
