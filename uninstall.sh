#!/usr/bin/env bash
# SuperMemory v2 -- uninstaller
# Removes hooks + slash commands + settings.json hook entries.
# Does NOT touch your vault content.

set -eu

HOOKS_DST="$HOME/.claude/hooks/supermemory"
CMDS_DST="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "SuperMemory v2 -- uninstaller"
echo ""

# 1) Remove hooks dir.
[ -d "$HOOKS_DST" ] && { rm -rf "$HOOKS_DST"; echo "  removed $HOOKS_DST"; }

# 2) Remove slash commands.
rm -f "$CMDS_DST/recap.md" "$CMDS_DST/peers.md"
echo "  removed $CMDS_DST/{recap,peers}.md"

# 3) Strip SuperMemory hook entries from settings.json.
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '
    (.hooks // {}) as $h |
    .hooks = (
      $h |
      to_entries |
      map(.value |= map(select(
        (.hooks // []) | all(.command // "" | contains("supermemory") | not)
      ))) |
      map(select(.value | length > 0)) |
      from_entries
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "  stripped supermemory hook entries from $SETTINGS"
fi

cat <<DONE

Uninstalled.

Note: your vault content at \$SUPERMEMORY_VAULT_DIR is untouched. To wipe sessions:
  rm -rf "\$SUPERMEMORY_VAULT_DIR/SuperMemory"
DONE
