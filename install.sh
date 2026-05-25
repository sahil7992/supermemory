#!/usr/bin/env bash
# SuperMemory -- installer
# Wires Claude Code hooks + slash commands + templates into the user's environment.
# Usage: bash install.sh [vault_path]

set -euo pipefail

VAULT="${1:-${SUPERMEMORY_VAULT_DIR:-$HOME/Documents/Obsidian Vault}}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DST="$HOME/.claude/hooks/supermemory"
CMDS_DST="$HOME/.claude/commands"
SETTINGS="$HOME/.claude/settings.json"

echo "SuperMemory -- installer"
echo "  Repo:   $REPO_DIR"
echo "  Vault:  $VAULT"
echo ""

# --- Dependency check ---
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: 'jq' is required (brew install jq / apt install jq)"
  exit 1
}
command -v claude >/dev/null 2>&1 || {
  echo "WARNING: 'claude' CLI not in PATH. Headless summarizer will be skipped at runtime."
}

# --- Install hook scripts ---
echo "1) Installing hooks → $HOOKS_DST"
mkdir -p "$HOOKS_DST"
cp "$REPO_DIR/hooks/"*.sh "$HOOKS_DST/"
cp "$REPO_DIR/prompts/summarizer.md" "$HOOKS_DST/summarizer.md"
chmod +x "$HOOKS_DST/"*.sh

# --- Install slash commands ---
echo "2) Installing slash commands → $CMDS_DST"
mkdir -p "$CMDS_DST"
cp "$REPO_DIR/commands/"*.md "$CMDS_DST/"

# --- Install templates into vault ---
echo "3) Installing templates → $VAULT/Templates"
mkdir -p "$VAULT/Templates"
cp "$REPO_DIR/templates/"*.md "$VAULT/Templates/"

# --- Vault skeleton ---
echo "4) Ensuring vault skeleton"
mkdir -p \
  "$VAULT/SuperMemory" \
  "$VAULT/Projects" \
  "$VAULT/People" \
  "$VAULT/Work/Tickets" \
  "$VAULT/Work/Curantis" \
  "$VAULT/Concepts" \
  "$VAULT/Playbooks" \
  "$VAULT/Feedback" \
  "$VAULT/Sources" \
  "$VAULT/Tax" \
  "$VAULT/Archive" \
  "$VAULT/.logs"

# Seed Index.md if absent.
SM_INDEX="$VAULT/SuperMemory/Index.md"
if [ ! -f "$SM_INDEX" ]; then
  cat > "$SM_INDEX" <<'IDX'
# SuperMemory Index

> Auto-maintained session log. Most recent at top. Each entry is one line.

IDX
  echo "   seeded $SM_INDEX"
fi

# --- Patch settings.json hooks (merge) ---
echo "5) Patching $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp=$(mktemp)
jq '
  .hooks //= {} |
  .hooks.SessionStart //= [] |
  .hooks.SessionStart += [{
    "matcher": "startup|resume",
    "hooks": [{"type":"command","command":"bash ~/.claude/hooks/supermemory/on-session-start.sh","timeout":5}]
  }] |
  .hooks.SessionEnd //= [] |
  .hooks.SessionEnd += [{
    "hooks": [{"type":"command","command":"bash ~/.claude/hooks/supermemory/on-session-end.sh","async":true,"timeout":5}]
  }] |
  .hooks.PreCompact //= [] |
  .hooks.PreCompact += [{
    "hooks": [{"type":"command","command":"bash ~/.claude/hooks/supermemory/on-summarize.sh","async":true,"timeout":5}]
  }] |
  .hooks.UserPromptSubmit //= [] |
  .hooks.UserPromptSubmit += [{
    "hooks": [{"type":"command","command":"bash ~/.claude/hooks/supermemory/on-prompt.sh","async":true,"timeout":2}]
  }] |
  .hooks.PreToolUse //= [] |
  .hooks.PreToolUse += [{
    "matcher": "Edit|Write",
    "hooks": [{"type":"command","command":"bash ~/.claude/hooks/supermemory/on-edit.sh","async":true,"timeout":2}]
  }]
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
echo "   hooks merged into $SETTINGS"

# --- Custom vault path note ---
if [ "$VAULT" != "$HOME/Documents/Obsidian Vault" ]; then
  echo ""
  echo "6) Custom vault path. Add to your shell profile (~/.zshrc):"
  echo "     export SUPERMEMORY_VAULT_DIR=\"$VAULT\""
fi

cat <<DONE

Installed.

Next steps:
  • Restart Claude Code so hooks load.
  • Optional: bash $REPO_DIR/scripts/revive-wiki.sh    (scaffolds wiki hubs)
  • Optional: bash $REPO_DIR/scripts/backfill.sh       (catches up past sessions)
  • Inside a session, run: /snapshot   /peers
  • Logs: $VAULT/.logs/

DONE
