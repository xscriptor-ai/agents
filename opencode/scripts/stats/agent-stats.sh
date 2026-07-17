#!/usr/bin/env bash
# agent-stats.sh - Statistics about the agent collection.
# Usage: ./stats/agent-stats.sh [--agents PATH] [--format text|json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="${SCRIPT_DIR}/agents"
FORMAT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents) AGENTS_DIR="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

declare -A GROUP_COUNTS
declare -A TEMP_BUCKETS
declare -A COLOR_COUNTS
declare -A PERM_COUNTS
TOTAL_LINES=0
TOTAL_FILES=0

while IFS= read -r -d '' file; do
  GROUP=$(basename "$(dirname "$file")")
  GROUP_COUNTS["$GROUP"]=$((GROUP_COUNTS["$GROUP"] + 1))
  ((TOTAL_FILES++))
  LINES=$(wc -l < "$file")
  TOTAL_LINES=$((TOTAL_LINES + LINES))

  content=$(<"$file")

  if grep -q '^temperature:' <<< "$content"; then
    temp_val=$(grep '^temperature:' <<< "$content" | head -1 | sed 's/.*: *//')
    bucket=$(awk "BEGIN {printf \"%.1f\", int($temp_val * 10) / 10}")
    TEMP_BUCKETS["$bucket"]=$((TEMP_BUCKETS["$bucket"] + 1))
  fi

  if grep -q '^color:' <<< "$content"; then
    color_val=$(grep '^color:' <<< "$content" | head -1 | sed 's/.*: *//' | tr -d '"')
    COLOR_COUNTS["$color_val"]=$((COLOR_COUNTS["$color_val"] + 1))
  fi

  for tool in edit bash glob grep read list webfetch; do
    if grep -qi "$tool:" <<< "$content"; then
      val=$(grep -i "$tool:" <<< "$content" | head -1 | sed 's/.*:[[:space:]]*//')
      PERM_COUNTS["$tool|$val"]=$((PERM_COUNTS["$tool|$val"] + 1))
    fi
  done
done < <(find "$AGENTS_DIR" -name '*.md' ! -name 'README.md' -print0 2>/dev/null)

if [[ "$FORMAT" == "json" ]]; then
  echo "{"
  echo "  \"total_agents\": $TOTAL_FILES,"
  echo "  \"avg_lines\": $((TOTAL_FILES > 0 ? TOTAL_LINES / TOTAL_FILES : 0)),"
  echo "  \"groups\": ["
  FIRST=true
  for g in "${!GROUP_COUNTS[@]}"; do
    $FIRST || echo ","
    FIRST=false
    echo -n "    {\"group\": \"$g\", \"count\": ${GROUP_COUNTS[$g]}}"
  done
  echo ""
  echo "  ]"
  echo "}"
else
  echo "==> Agent Statistics"
  echo ""
  echo "Total agents: $TOTAL_FILES"
  echo "Average lines per agent: $((TOTAL_FILES > 0 ? TOTAL_LINES / TOTAL_FILES : 0))"
  echo ""
  echo "By group:"
  for g in "${!GROUP_COUNTS[@]}"; do
    printf "  %-25s %3d\n" "$g" "${GROUP_COUNTS[$g]}"
  done | sort -t' ' -k2 -rn
  echo ""
  echo "Temperature distribution:"
  for t in 0.0 0.1 0.2 0.3 0.4 0.5; do
    printf "  %.1f: %3d agents\n" "$t" "${TEMP_BUCKETS[$t]:-0}"
  done
  echo ""
  echo "Most used colors:"; 
  for c in "${!COLOR_COUNTS[@]}"; do
    printf "  %-15s %3d\n" "$c" "${COLOR_COUNTS[$c]}"
  done | sort -t' ' -k2 -rn | head -5
fi
