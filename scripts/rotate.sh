#!/usr/bin/env bash
# SuperMemory v2 -- archive sessions older than N days
# Usage: bash rotate.sh [days_default_30] [vault_path]

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../hooks/lib.sh"

DAYS="${1:-30}"
[ $# -ge 2 ] && SM_VAULT="$2"

SRC="$SM_VAULT/SuperMemory"
DST="$SM_VAULT/Archive/$(date +%Y-%m)"
mkdir -p "$DST"

[ -d "$SRC" ] || { echo "No SuperMemory dir at $SRC"; exit 1; }

CUTOFF_EPOCH=$(date -v-"$DAYS"d +%s 2>/dev/null || date -d "$DAYS days ago" +%s)
MOVED=0
for f in "$SRC"/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  [ "$base" = "Index.md" ] && continue
  mtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null) || continue
  if [ "$mtime" -lt "$CUTOFF_EPOCH" ]; then
    mv "$f" "$DST/$base"
    MOVED=$((MOVED+1))
  fi
done

echo "Archived $MOVED file(s) older than $DAYS days to $DST"
