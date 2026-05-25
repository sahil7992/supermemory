#!/usr/bin/env bash
# SuperMemory -- wiki health check
# Detects: dead wikilinks, orphan pages, stale hubs (no session ref in 30 days).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/../hooks/lib.sh"

VAULT="$SM_VAULT"
cd "$VAULT" 2>/dev/null || { echo "No vault at $VAULT"; exit 1; }

echo "Lint -- $VAULT"
echo ""

# All page filenames (without .md) inside the vault.
ALL_PAGES=$(find . -name "*.md" -not -path "./.obsidian/*" -not -path "./.logs/*" -not -path "./Archive/*" 2>/dev/null | sed 's|^\./||; s|\.md$||')

# All wikilink targets across the vault.
ALL_TARGETS=$(find . -name "*.md" -not -path "./.obsidian/*" -not -path "./.logs/*" -exec grep -hoE '\[\[[^]|]+(\|[^]]+)?\]\]' {} \; 2>/dev/null | sed 's/\[\[//; s/\]\]//; s/|.*//' | sort -u)

# --- Dead links: targets that don't match any page (by basename or full path) ---
echo "## Dead wikilinks"
DEAD=0
while IFS= read -r target; do
  [ -z "$target" ] && continue
  # Try basename match anywhere in vault.
  base=$(basename "$target")
  found=$(echo "$ALL_PAGES" | grep -F -x "$target" -o -x "$base" 2>/dev/null | head -1)
  # Also try: page basename matches.
  if [ -z "$found" ]; then
    found=$(echo "$ALL_PAGES" | awk -F/ -v b="$base" '$NF==b {print; exit}')
  fi
  if [ -z "$found" ]; then
    echo "  - [[$target]]"
    DEAD=$((DEAD+1))
  fi
done <<< "$ALL_TARGETS"
[ "$DEAD" -eq 0 ] && echo "  (none)"
echo ""

# --- Orphan pages: pages with zero inbound links ---
echo "## Orphan pages (no inbound links)"
ORPHANS=0
while IFS= read -r page; do
  [ -z "$page" ] && continue
  base=$(basename "$page")
  # Skip intentional roots.
  case "$base" in
    Home|index|log|Index|"Source Summary"|"Entity Page"|"Concept Page"|"session"|"project-hub"|"person-hub"|"concept-hub"|"ticket-hub") continue ;;
  esac
  hits=$(echo "$ALL_TARGETS" | grep -F -c -x "$base" 2>/dev/null)
  hits=${hits:-0}
  if [ "$hits" -eq 0 ]; then
    echo "  - $page.md"
    ORPHANS=$((ORPHANS+1))
  fi
done <<< "$ALL_PAGES"
[ "$ORPHANS" -eq 0 ] && echo "  (none)"
echo ""

# --- Stale hubs: pages in Projects/People/Concepts with no "Recent sessions" bullet from last 30 days ---
echo "## Stale hubs (no session bullet in last 30 days)"
CUTOFF=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)
STALE=0
for d in Projects People Concepts Work/Tickets; do
  [ -d "$VAULT/$d" ] || continue
  for hub in "$VAULT/$d"/*.md; do
    [ -r "$hub" ] || continue
    # Look for a date >= cutoff inside the file.
    recent=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$hub" 2>/dev/null | sort -u | awk -v c="$CUTOFF" '$1 >= c' | head -1)
    if [ -z "$recent" ]; then
      echo "  - $d/$(basename "$hub")"
      STALE=$((STALE+1))
    fi
  done
done
[ "$STALE" -eq 0 ] && echo "  (none)"
echo ""

echo "Summary: $DEAD dead, $ORPHANS orphans, $STALE stale."
