#!/usr/bin/env bash
# SuperMemory v2 -- shared helpers
# Sourced by all hooks. Provides: atomic writes, paths, jq sanity, peer-registry I/O.

set -u

# --- Paths -------------------------------------------------------------------

SM_VAULT="${SUPERMEMORY_VAULT_DIR:-$HOME/Documents/Obsidian Vault}"
SM_LOGS="$SM_VAULT/.logs"
SM_PEERS="$HOME/.claude/sessions"
SM_HOOKS_DIR="$HOME/.claude/hooks/supermemory"
SM_PROMPT="$SM_HOOKS_DIR/summarizer.md"

# --- Locking ----------------------------------------------------------------
# macOS has lockf; Linux has flock. Both wrap a command so file access serializes.

sm_lock() {
  local file="$1"; shift
  if command -v lockf >/dev/null 2>&1; then
    lockf -t 5 "$file" "$@"
  elif command -v flock >/dev/null 2>&1; then
    flock -w 5 "$file" "$@"
  else
    "$@"
  fi
}

# --- Atomic append ----------------------------------------------------------
# Append content to a file under a lock. Creates parent dir if missing.
sm_append() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  local lockfile="${file}.lock"
  touch "$lockfile"
  sm_lock "$lockfile" bash -c "cat >> '$file'" <<< "$*"
}

# --- Logging ----------------------------------------------------------------
sm_log() {
  mkdir -p "$SM_LOGS"
  echo "[$(date +%Y-%m-%dT%H:%M:%S)] $*" >> "$SM_LOGS/$(date +%Y%m%d).log"
}

# --- JSON sanity ------------------------------------------------------------
sm_have_jq() { command -v jq >/dev/null 2>&1; }

sm_jq_field() {
  if sm_have_jq; then jq -r "$1 // empty" 2>/dev/null; else cat >/dev/null; fi
}

# --- Transcript helpers -----------------------------------------------------
sm_user_turn_count() {
  local transcript="$1"
  [ -r "$transcript" ] || { echo 0; return; }
  if sm_have_jq; then
    jq -s 'map(select(.type=="user" and ((.message.content|type)=="string") and ((.message.content|startswith("<"))|not))) | length' "$transcript" 2>/dev/null || echo 0
  else
    grep -c '"type":"user"' "$transcript" 2>/dev/null || echo 0
  fi
}

# --- Peer registry I/O ------------------------------------------------------
sm_peer_file() { echo "$SM_PEERS/$1.json"; }

sm_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

sm_peer_init() {
  local session_id="$1" cwd="$2"
  local file; file=$(sm_peer_file "$session_id")
  mkdir -p "$SM_PEERS"
  local now; now=$(sm_now_iso)
  cat > "$file" <<JSON
{
  "session_id": "$session_id",
  "cwd": "$cwd",
  "started_at": "$now",
  "last_active": "$now",
  "last_prompt": "",
  "topic": "",
  "active_files": []
}
JSON
}

sm_peer_update() {
  local session_id="$1" field="$2" value="$3"
  local file; file=$(sm_peer_file "$session_id")
  [ -f "$file" ] || return 0
  sm_have_jq || return 0
  local lockfile="${file}.lock"
  touch "$lockfile"
  sm_lock "$lockfile" bash -c "
    tmp=\$(mktemp)
    jq --arg v '$value' --arg t '$(sm_now_iso)' '.[\"$field\"]=\$v | .last_active=\$t' '$file' > \"\$tmp\" && mv \"\$tmp\" '$file'
  "
}

sm_peer_add_file() {
  local session_id="$1" path="$2"
  local file; file=$(sm_peer_file "$session_id")
  [ -f "$file" ] || return 0
  sm_have_jq || return 0
  local lockfile="${file}.lock"
  touch "$lockfile"
  sm_lock "$lockfile" bash -c "
    tmp=\$(mktemp)
    jq --arg p '$path' --arg t '$(sm_now_iso)' '.active_files = ([.active_files[], \$p] | unique | .[-5:]) | .last_active=\$t' '$file' > \"\$tmp\" && mv \"\$tmp\" '$file'
  "
}

sm_peer_sweep() {
  [ -d "$SM_PEERS" ] || return 0
  local cutoff
  cutoff=$(date -u -v-4H +%s 2>/dev/null || date -u -d '4 hours ago' +%s 2>/dev/null) || return 0
  for f in "$SM_PEERS"/*.json; do
    [ -f "$f" ] || continue
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || continue
    [ "$mtime" -lt "$cutoff" ] && rm -f "$f" "${f}.lock"
  done
}

sm_peer_remove() {
  local session_id="$1"
  rm -f "$(sm_peer_file "$session_id")" "$(sm_peer_file "$session_id").lock"
}

# List active peers (excluding current session). One JSON object per line.
sm_peer_list_others() {
  local self="$1"
  [ -d "$SM_PEERS" ] || return 0
  for f in "$SM_PEERS"/*.json; do
    [ -f "$f" ] || continue
    [ "$(basename "$f" .json)" = "$self" ] && continue
    cat "$f"
  done
}
