#!/usr/bin/env bash
# SuperMemory v2 -- SessionStart hook
# Outputs ~500-650 bytes of additionalContext: recent sessions + cwd-matching hub + active peers.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID=$(echo "$INPUT" | sm_jq_field '.session_id')
CWD=$(echo "$INPUT" | sm_jq_field '.cwd')

# Register self in peer registry and sweep stale peers.
[ -n "$SESSION_ID" ] && sm_peer_init "$SESSION_ID" "$CWD"
sm_peer_sweep

INDEX="$SM_VAULT/SuperMemory/Index.md"
PROJECTS_DIR="$SM_VAULT/Projects"

# --- Recent sessions: last 2 entries, sanitized + truncated to 180 chars ---
# Strip UTF-8 (em-dashes, smart quotes) so byte-truncation can't produce invalid sequences.
RECENT=""
if [ -r "$INDEX" ]; then
  RECENT=$(grep -E '^- \[\[' "$INDEX" 2>/dev/null \
    | head -2 \
    | LC_ALL=C sed 's/[^[:print:][:space:]]//g; s/  */ /g' \
    | awk '{ s=$0; if (length(s)>180) s=substr(s,1,180) "..."; print "  " s }')
fi

# --- cwd-matching hub: scan Projects/*.md for `directory:` matching CWD ---
HUB_LINE=""
if [ -n "$CWD" ] && [ -d "$PROJECTS_DIR" ]; then
  for hub in "$PROJECTS_DIR"/*.md; do
    [ -r "$hub" ] || continue
    hub_dir=$(grep -E '^directory:' "$hub" 2>/dev/null | head -1 | sed 's/^directory: *//; s/"//g')
    case "$CWD" in
      "$hub_dir"*)
        hub_name=$(basename "$hub" .md)
        hub_summary=$(grep -E '^> ' "$hub" 2>/dev/null | head -1 | sed 's/^> //' | LC_ALL=C sed 's/[^[:print:][:space:]]//g' | awk '{ if (length($0)>140) print substr($0,1,140) "..."; else print $0 }')
        HUB_LINE="  [[Projects/$hub_name]] -- $hub_summary"
        break
        ;;
    esac
  done
fi

# --- Active peers (other running sessions) ---
PEERS=""
if [ -n "$SESSION_ID" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    p_cwd=$(echo "$line" | sm_jq_field '.cwd')
    p_topic=$(echo "$line" | sm_jq_field '.topic')
    p_prompt=$(echo "$line" | sm_jq_field '.last_prompt')
    p_short=${p_topic:-$p_prompt}
    p_short=$(echo "$p_short" | cut -c1-60)
    p_base=$(basename "$p_cwd")
    PEERS="$PEERS  [$p_base: \"$p_short\"]"
  done < <(sm_peer_list_others "$SESSION_ID" | jq -c '.' 2>/dev/null)
fi

# --- Build additionalContext ---
CONTEXT="## SuperMemory breadcrumbs (lazy-load only)"
[ -n "$RECENT" ] && CONTEXT="$CONTEXT
Recent sessions:
$RECENT"
[ -n "$HUB_LINE" ] && CONTEXT="$CONTEXT
Project hub for this cwd:
$HUB_LINE"
[ -n "$PEERS" ] && CONTEXT="$CONTEXT
Active peers:$PEERS"
CONTEXT="$CONTEXT

To recall: \`grep \$VAULT/SuperMemory/Index.md\` for keywords, then read the specific session file. Don't pre-load. To checkpoint mid-session: \`/recap\`. To see live peers: \`/peers\`."

# Emit hook output.
if sm_have_jq; then
  jq -n --arg c "$CONTEXT" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$c}}'
else
  # Minimal fallback without jq -- escape quotes.
  esc=$(echo "$CONTEXT" | sed 's/"/\\"/g; s/$/\\n/' | tr -d '\n')
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$esc"
fi

exit 0
