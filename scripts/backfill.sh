#!/usr/bin/env bash
# SuperMemory -- backfill summaries for the gap between latest Index entry and now.
# Walks ~/.claude/projects/**/*.jsonl with mtime after the latest date in SuperMemory/Index.md,
# fires on-summarize.sh against each. Sequential to avoid API thrashing.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../hooks/lib.sh"

INDEX="$SM_VAULT/SuperMemory/Index.md"
ON_SUMMARIZE="$SM_HOOKS_DIR/on-summarize.sh"
[ -x "$ON_SUMMARIZE" ] || ON_SUMMARIZE="$SCRIPT_DIR/../hooks/on-summarize.sh"

# Last date present in Index. Defaults to 60 days ago if no Index.
LAST_DATE=""
if [ -r "$INDEX" ]; then
  LAST_DATE=$(grep -oE '## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$INDEX" 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$LAST_DATE" ]; then
  LAST_DATE=$(date -v-60d +%Y-%m-%d 2>/dev/null || date -d '60 days ago' +%Y-%m-%d)
fi

echo "Backfill -- summarizing transcripts modified after $LAST_DATE"
echo ""

# Convert LAST_DATE to epoch
LAST_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_DATE" "+%s" 2>/dev/null || date -d "$LAST_DATE" +%s)

COUNT=0
SKIP=0
for jsonl in "$HOME/.claude/projects/"*/*.jsonl; do
  [ -f "$jsonl" ] || continue
  mtime=$(stat -f %m "$jsonl" 2>/dev/null || stat -c %Y "$jsonl" 2>/dev/null) || continue
  [ "$mtime" -le "$LAST_EPOCH" ] && { SKIP=$((SKIP+1)); continue; }

  # Skip trivial transcripts.
  turns=$(sm_user_turn_count "$jsonl")
  turns=${turns:-0}
  if [ "$turns" -lt 5 ]; then SKIP=$((SKIP+1)); continue; fi

  # Derive cwd from the dir name (path-encoded).
  proj_dir=$(basename "$(dirname "$jsonl")")
  cwd=$(echo "$proj_dir" | sed 's/^-//; s/-/\//g')
  cwd="/$cwd"
  session_id=$(basename "$jsonl" .jsonl)

  echo "[backfill] $(date -r "$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null) $(basename "$jsonl") (turns=$turns, cwd=$cwd)"
  echo "{\"transcript_path\":\"$jsonl\",\"session_id\":\"$session_id\",\"cwd\":\"$cwd\",\"hook_event_name\":\"backfill\"}" | "$ON_SUMMARIZE"

  COUNT=$((COUNT+1))
  sleep 8  # space out Haiku spawns
done

echo ""
echo "Dispatched $COUNT summarizations; skipped $SKIP (older than $LAST_DATE or trivial)."
echo "Tail $SM_LOGS/$(date +%Y%m%d)-summarizer.log to watch progress."
