#!/usr/bin/env bash
# build-docs.sh - Generate combined documentation for all agents and scripts.
# Usage: ./docs/build-docs.sh [--output PATH] [--format markdown|html]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/agents"
OUTPUT="${SCRIPT_DIR}/AGENTS-COMPLETE.md"
FORMAT="markdown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

{
  echo "# OpenCode Agents — Complete Reference"
  echo ""
  echo "Generated: $(date '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Repository: https://github.com/xscriptor/ai"
  echo ""

  TOTAL=0
  while IFS= read -r -d '' readme; do
    GROUP=$(basename "$(dirname "$readme")")
    PARENT=$(basename "$(dirname "$(dirname "$readme")")")
    if [[ "$PARENT" != "agents" && "$PARENT" != "." ]]; then
      GROUP="${PARENT}/${GROUP}"
    fi
    COUNT=$(find "$(dirname "$readme")" -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')
    TOTAL=$((TOTAL + COUNT))
    echo "## ${GROUP}"
    echo ""
    echo "**${COUNT} agents**"
    echo ""

    if [[ -f "$readme" ]]; then
      # Extract agent rows from the table in the group README
      while IFS= read -r line; do
        if [[ "$line" =~ \<tr\>.*\<td\>.*\<\/td\>.*\<\/tr\> ]]; then
          echo "- $line"
        fi
      done < <(grep -i '<tr><td>' "$readme" | head -20)
    fi
    echo ""
  done < <(find "$AGENTS_DIR" -name 'README.md' -print0 | sort -z)

  echo "---"
  echo "**Total: ${TOTAL} agents**"
} > "$OUTPUT"

echo "==> Generated: $OUTPUT ($(wc -l < "$OUTPUT") lines)"
