#!/usr/bin/env bash
# SuperMemory rotation — moves sessions older than 30 days to Archive/
# Usage: bash rotate.sh [vault_path] [days]
set -euo pipefail

VAULT_DIR="${1:-$HOME/Documents/Obsidian Vault/SuperMemory}"
DAYS="${2:-30}"

SESSIONS_DIR="$VAULT_DIR/Sessions"
ARCHIVE_DIR="$VAULT_DIR/Archive"

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "Sessions directory not found: $SESSIONS_DIR"
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"

count=0
find "$SESSIONS_DIR" -name "*.md" -mtime "+${DAYS}" -type f | while read -r file; do
  mv "$file" "$ARCHIVE_DIR/"
  echo "Archived: $(basename "$file")"
  count=$((count + 1))
done

echo "Done. Archived $count session(s) older than $DAYS days."
