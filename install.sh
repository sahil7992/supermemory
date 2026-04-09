#!/usr/bin/env bash
# SuperMemory installer — sets up Claude Code hooks for Obsidian logging
# Usage: bash install.sh [vault_path]
set -euo pipefail

VAULT_DIR="${1:-$HOME/Documents/Obsidian Vault/SuperMemory}"
HOOKS_DIR="$HOME/.claude/hooks/supermemory"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "SuperMemory Installer"
echo "====================="
echo ""

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed."
  echo "  macOS: brew install jq"
  echo "  Linux: sudo apt install jq"
  exit 1
fi

if ! command -v lockf &>/dev/null && ! command -v flock &>/dev/null; then
  echo "WARNING: Neither lockf nor flock found. File locking will be disabled."
  echo "  This is fine for single-session use, but concurrent sessions may have write conflicts."
fi

# Install hook scripts
echo "1. Installing hook scripts to $HOOKS_DIR ..."
mkdir -p "$HOOKS_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/hooks/lib.sh" "$HOOKS_DIR/lib.sh"
cp "$SCRIPT_DIR/hooks/dispatcher.sh" "$HOOKS_DIR/dispatcher.sh"
chmod +x "$HOOKS_DIR/lib.sh" "$HOOKS_DIR/dispatcher.sh"
echo "   Done."

# Create Obsidian directories
echo "2. Creating Obsidian vault directories at $VAULT_DIR ..."
mkdir -p "$VAULT_DIR/Sessions" "$VAULT_DIR/Agents" "$VAULT_DIR/Errors"

if [ ! -f "$VAULT_DIR/Index.md" ]; then
  cat > "$VAULT_DIR/Index.md" << 'IDX'
# SuperMemory Index

> Auto-updated map of all Claude Code sessions logged to Obsidian.
> Every prompt, tool call, agent spawn, and response — captured automatically via hooks.

## Recent Sessions

IDX
  echo "   Created Index.md"
fi
echo "   Done."

# Configure hooks in settings.json
echo "3. Configuring Claude Code hooks ..."

if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Check if hooks already configured
if jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
  echo "   WARNING: hooks already exist in $SETTINGS_FILE"
  echo "   Skipping hook configuration to avoid overwriting existing hooks."
  echo "   To configure manually, add the following to your settings.json hooks section:"
  echo ""
  echo '   "SessionStart": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SessionStart"}]'
  echo '   "UserPromptSubmit": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh UserPromptSubmit"}]'
  echo '   "PreToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PreToolUse"}]}]'
  echo '   "PostToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PostToolUse"}]}]'
  echo '   "Stop": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh Stop"}]'
  echo '   "SubagentStop": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SubagentStop"}]'
else
  # Add hooks to settings.json
  local_tmp=$(mktemp)
  jq '. + {
    "hooks": {
      "SessionStart": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SessionStart"}],
      "UserPromptSubmit": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh UserPromptSubmit"}],
      "PreToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PreToolUse"}]}],
      "PostToolUse": [{"matcher": ".*", "hooks": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh PostToolUse"}]}],
      "Stop": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh Stop"}],
      "SubagentStop": [{"type": "command", "command": "bash ~/.claude/hooks/supermemory/dispatcher.sh SubagentStop"}]
    }
  }' "$SETTINGS_FILE" > "$local_tmp" && mv "$local_tmp" "$SETTINGS_FILE"
  echo "   Done."
fi

# Set custom vault path if provided
if [ "$VAULT_DIR" != "$HOME/Documents/Obsidian Vault/SuperMemory" ]; then
  echo ""
  echo "4. Custom vault path detected."
  echo "   Add this to your shell profile (~/.zshrc or ~/.bashrc):"
  echo ""
  echo "   export SUPERMEMORY_VAULT_DIR=\"$VAULT_DIR\""
  echo ""
fi

echo ""
echo "Installation complete!"
echo ""
echo "IMPORTANT: Restart Claude Code for hooks to take effect."
echo "  (Hooks are only loaded at session start)"
echo ""
echo "Your sessions will be logged to: $VAULT_DIR/Sessions/"
echo "Agent notes: $VAULT_DIR/Agents/"
echo "Error notes: $VAULT_DIR/Errors/"
echo "Session index: $VAULT_DIR/Index.md"
