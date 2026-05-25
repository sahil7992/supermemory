#!/usr/bin/env bash
# SuperMemory v2 — wiki revival (one-shot)
# Walks ~/.claude/projects/-Users-sahilpambhar/memory/*.md and scaffolds wiki hubs.
# Strategy: don't migrate content. Create stub hubs that REFERENCE Claude memory as source.
# The auto-summarizer fills in "Recent sessions" over time as sessions touch each entity.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib.sh
. "$SCRIPT_DIR/../hooks/lib.sh"

VAULT="$SM_VAULT"
MEM="$HOME/.claude/projects/-Users-sahilpambhar/memory"
TPL="$SCRIPT_DIR/../templates"
DRY_RUN="${DRY_RUN:-0}"

echo "Revive Wiki — SuperMemory v2"
echo "  Vault:  $VAULT"
echo "  Memory: $MEM"
echo "  Dry-run: $DRY_RUN"
echo ""

[ -d "$MEM" ] || { echo "No Claude memory dir at $MEM"; exit 1; }
[ -d "$VAULT" ] || { echo "Vault missing: $VAULT"; exit 1; }

# Ensure structure exists.
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
  "$VAULT/Templates" \
  "$VAULT/.logs"

# --- Mapping: source memory file -> (target dir, template, display name) ---
# Format: "memory_file|target_dir|template|Display Name"
MAP=$(cat <<'EOF'
curantis-ai-project.md|Projects|project-hub.md|Curantis AI
healthlake-upgrade-ticket.md|Work/Tickets|ticket-hub.md|HealthLake Upgrade
mec-redshift-pipeline-investigation.md|Work/Tickets|ticket-hub.md|MEC Redshift Pipeline
accrual-revenue-prior-month.md|Work/Tickets|ticket-hub.md|Accrual Revenue Prior Month
ar-aging-ticket-context.md|Work/Tickets|ticket-hub.md|AR Aging
fact-daily-census-pipeline-fix.md|Work/Tickets|ticket-hub.md|Fact Daily Census Pipeline
curantis-layoffs-2026.md|Work/Curantis|concept-hub.md|Layoffs 2026
jasper-report-skill.md|Concepts|concept-hub.md|Jasper Reports
jasper-reports-fixes-apr2026.md|Concepts|concept-hub.md|Jasper Fixes Apr 2026
dms-debugging-playbook.md|Playbooks|concept-hub.md|DMS Debugging
tenant-onboarding-playbook.md|Playbooks|concept-hub.md|Tenant Onboarding
kaalsync_startup.md|Projects|project-hub.md|KaalSync
llm-wiki-project.md|Projects|project-hub.md|LLM Wiki (predecessor)
tax-filing-2025.md|Tax|concept-hub.md|2025 Tax Filing
EOF
)

# Special: combine sahil-{profile,employment,finances} into one People hub.
combine_sahil_hub() {
  local target="$VAULT/People/Sahil Pambhar.md"
  if [ -f "$target" ]; then echo "  [skip] People/Sahil Pambhar.md exists"; return; fi
  local sources=""
  for f in sahil-profile.md sahil-employment.md sahil-finances.md; do
    [ -r "$MEM/$f" ] && sources="$sources\n  - \`$MEM/$f\`"
  done
  if [ "$DRY_RUN" = "1" ]; then echo "  [dry] would create $target"; return; fi
  cat > "$target" <<HUB
---
type: person
name: Sahil Pambhar
role: Software Engineer (Curantis Solutions, full-time April 2026)
relationship: self
tags: [person, self]
---

# Sahil Pambhar

> This is me. STEM-OPT, MacBook, KaalSync builder, Curantis dev.

## Context

Canonical operational facts about Sahil live in Claude memory (not duplicated here to avoid drift). This page exists so SuperMemory sessions can link \`[[People/Sahil Pambhar]]\`.

## Sources (canonical)
$(printf '%b' "$sources")

## Recent sessions

<!-- AUTO-APPENDED by SuperMemory summarizer. Newest at top. -->

## Connections

- [[Projects/Curantis AI]]
- [[Projects/KaalSync]]
- [[Work/Curantis/Layoffs 2026]]
HUB
  echo "  [new] People/Sahil Pambhar.md"
}

# Create a generic hub from a memory file.
create_hub() {
  local mem_file="$1" target_dir="$2" template="$3" display="$4"
  local mem_path="$MEM/$mem_file"
  local target="$VAULT/$target_dir/$display.md"

  [ -r "$mem_path" ] || { echo "  [miss] $mem_file (no source)"; return; }
  if [ -f "$target" ]; then echo "  [skip] $target_dir/$display.md exists"; return; fi

  # Extract one-line description from source if present (first non-empty non-frontmatter line).
  local desc
  desc=$(awk 'BEGIN{f=0} /^---$/{f++;next} f==2 && NF>0 {print; exit}' "$mem_path" 2>/dev/null | head -c 200)
  desc="${desc:-See source file for details.}"

  if [ "$DRY_RUN" = "1" ]; then echo "  [dry] would create $target"; return; fi

  case "$template" in
    project-hub.md)
      cat > "$target" <<HUB
---
type: project
name: $display
status: active
tags: [project]
---

# $display

> $desc

## Status

See \`$mem_path\` for current state.

## Sources (canonical)

- \`$mem_path\`

## Recent sessions

<!-- AUTO-APPENDED by SuperMemory summarizer. Newest at top. -->

## Connections

- [[People/Sahil Pambhar]]
HUB
      ;;
    ticket-hub.md)
      cat > "$target" <<HUB
---
type: ticket
title: $display
status: in_progress
tags: [ticket]
---

# $display

> $desc

## Sources (canonical)

- \`$mem_path\`

## Recent sessions

<!-- AUTO-APPENDED by SuperMemory summarizer. Newest at top. -->

## Connections

- [[Projects/Curantis AI]]
- [[People/Sahil Pambhar]]
HUB
      ;;
    concept-hub.md|*)
      cat > "$target" <<HUB
---
type: concept
name: $display
tags: [concept]
---

# $display

> $desc

## Sources (canonical)

- \`$mem_path\`

## Recent sessions

<!-- AUTO-APPENDED by SuperMemory summarizer. Newest at top. -->

## Connections

- [[People/Sahil Pambhar]]
HUB
      ;;
  esac
  echo "  [new] $target_dir/$display.md"
}

# Migrate feedback memories.
migrate_feedback() {
  for f in "$MEM"/feedback-*.md; do
    [ -r "$f" ] || continue
    local base
    base=$(basename "$f" .md | sed 's/^feedback-//')
    local title
    title=$(echo "$base" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
    local target="$VAULT/Feedback/$title.md"
    [ -f "$target" ] && { echo "  [skip] Feedback/$title.md exists"; continue; }
    if [ "$DRY_RUN" = "1" ]; then echo "  [dry] would create $target"; continue; fi
    local desc
    desc=$(awk 'BEGIN{f=0} /^---$/{f++;next} f==2 && NF>0 {print; exit}' "$f" 2>/dev/null | head -c 200)
    cat > "$target" <<HUB
---
type: feedback
name: $title
tags: [feedback]
---

# $title

> $desc

## Source (canonical)

- \`$f\`

## Connections

- [[People/Sahil Pambhar]]
HUB
    echo "  [new] Feedback/$title.md"
  done
}

# --- Fix Home.md / index.md / log.md ---
write_home() {
  local target="$VAULT/Home.md"
  if [ "$DRY_RUN" = "1" ]; then echo "  [dry] would rewrite $target"; return; fi
  cat > "$target" <<'HOME'
# Sahil's Second Brain

> **Start here → [[index]] · [[SuperMemory/Index]]**

This vault is the persistent knowledge layer for Sahil's Claude Code sessions. SuperMemory v2 auto-maintains it.

## Quick Links

- [[index]] — Wiki catalog (all hub pages)
- [[SuperMemory/Index]] — Chronological session log
- [[People/Sahil Pambhar]] — About me
- [[Projects/Curantis AI]] — Main project
- [[Projects/KaalSync]] — Side project
- [[log]] — Operations timeline

## How it works

1. **You work in Claude Code as normal.** Hooks run automatically in the background.
2. **SessionEnd / PreCompact / `/recap`** triggers the headless summarizer (Haiku 4.5) to write a session file + update relevant hubs here.
3. **SessionStart** injects a tiny breadcrumb so a new session knows what was just done — without dragging full history into context.
4. **`/peers`** shows what other Claude sessions are doing right now (cross-tmux-pane visibility).

Repo: <https://github.com/sahil7992/supermemory>
HOME
  echo "  [new] Home.md"
}

# --- Run ---
echo "Migrating feedback files..."
migrate_feedback

echo ""
echo "Creating consolidated People/Sahil Pambhar.md..."
combine_sahil_hub

echo ""
echo "Creating per-entity hubs..."
while IFS='|' read -r mem_file target_dir template display; do
  [ -z "$mem_file" ] && continue
  create_hub "$mem_file" "$target_dir" "$template" "$display"
done <<< "$MAP"

echo ""
echo "Rewriting Home.md..."
write_home

# --- Initialize SuperMemory/Index.md if missing ---
SM_INDEX="$VAULT/SuperMemory/Index.md"
if [ ! -f "$SM_INDEX" ] && [ "$DRY_RUN" != "1" ]; then
  cat > "$SM_INDEX" <<'IDX'
# SuperMemory Index

> Auto-maintained session log. Most recent at top. Each entry is one line.

IDX
  echo "  [new] SuperMemory/Index.md"
fi

# --- Append a revival entry to log.md ---
if [ "$DRY_RUN" != "1" ]; then
  LOG="$VAULT/log.md"
  TODAY=$(date +%Y-%m-%d)
  {
    [ ! -s "$LOG" ] && echo "# Operations Log\n"
    echo ""
    echo "## [$TODAY] revive | SuperMemory v2 wiki revival"
    echo "- Scaffolded hubs from \`~/.claude/projects/-Users-sahilpambhar/memory/\`"
    echo "- Fixed Home.md dead links (Sahil Pambhar, Curantis AI now resolvable)"
    echo "- See [[SuperMemory/2026-05-24_supermemory-v2-build]] for context"
  } >> "$LOG"
  echo "  [appended] log.md"
fi

echo ""
echo "Revival complete. Run again with DRY_RUN=1 to preview, or normally to apply."
