#!/usr/bin/env bash
# SuperMemory uninstaller — removes hooks but keeps your Obsidian data
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks/supermemory"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "SuperMemory Uninstaller"
echo "======================="
echo ""

# Remove hook scripts
if [ -d "$HOOKS_DIR" ]; then
  rm -rf "$HOOKS_DIR"
  echo "1. Removed hook scripts from $HOOKS_DIR"
else
  echo "1. Hook scripts not found (already removed?)"
fi

# Remove hooks from settings.json
if [ -f "$SETTINGS_FILE" ] && jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
  local_tmp=$(mktemp)
  jq 'del(.hooks)' "$SETTINGS_FILE" > "$local_tmp" && mv "$local_tmp" "$SETTINGS_FILE"
  echo "2. Removed hooks from $SETTINGS_FILE"
else
  echo "2. No hooks found in settings (already removed?)"
fi

# Clean up state files
rm -f /tmp/supermemory_* 2>/dev/null || true
echo "3. Cleaned up temp state files"

echo ""
echo "Uninstall complete."
echo ""
echo "NOTE: Your Obsidian session logs have NOT been deleted."
echo "They are still in your vault under SuperMemory/"
echo "Delete them manually if you want to remove all data."
