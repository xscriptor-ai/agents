#!/usr/bin/env bash
# validate-agents.sh - Validate all agent markdown files for correct frontmatter.
# Usage: ./validate/validate-agents.sh [--agents PATH] [--strict]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/agents"
STRICT_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents) AGENTS_DIR="$2"; shift 2 ;;
    --strict) STRICT_MODE=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

ERRORS=0
WARNINGS=0
FILES=0

while IFS= read -r -d '' file; do
  NAME=$(basename "$file")
  ((FILES++))
  content=$(<"$file")

  # 1. Must start with ---
  if [[ "$content" != ---* ]]; then
    echo "  ERROR: $NAME - missing frontmatter (must start with ---)"
    ((ERRORS++))
    continue
  fi

  # 2. Description required
  if ! grep -q '^description:' <<< "$content"; then
    echo "  ERROR: $NAME - missing description field"
    ((ERRORS++))
  fi

  # 3. Mode must be valid
  if grep -q '^mode:' <<< "$content"; then
    mode_val=$(grep '^mode:' <<< "$content" | head -1 | sed 's/.*: *//')
    if [[ "$mode_val" != "subagent" && "$mode_val" != "primary" && "$mode_val" != "all" ]]; then
      echo "  ERROR: $NAME - mode must be subagent, primary, or all (got: $mode_val)"
      ((ERRORS++))
    fi
  fi

  # 4. Temperature range
  if grep -q '^temperature:' <<< "$content"; then
    temp_val=$(grep '^temperature:' <<< "$content" | head -1 | sed 's/.*: *//')
    if ! awk "BEGIN {exit !($temp_val < 0 || $temp_val > 1)}" 2>/dev/null; then
      echo "  WARN: $NAME - temperature outside 0.0-1.0 range ($temp_val)"
      ((WARNINGS++))
    fi
  fi

  # 5. Color format
  if grep -q '^color:' <<< "$content"; then
    color_val=$(grep '^color:' <<< "$content" | head -1 | sed 's/.*: *//' | tr -d '"')
    if ! [[ "$color_val" =~ ^#?[0-9a-fA-F]{6}$ || "$color_val" =~ ^(primary|secondary|accent|error|warning|success|info)$ ]]; then
      echo "  WARN: $NAME - unusual color format ($color_val)"
      ((WARNINGS++))
    fi
  fi

  # 6. Permission values
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*(allow|ask|deny)$ ]]; then
      : # valid
    elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z_]+:[[:space:]]*[a-zA-Z_*] ]]; then
      perm_val=$(echo "$line" | sed 's/.*:[[:space:]]*//')
      if [[ "$perm_val" != "allow" && "$perm_val" != "ask" && "$perm_val" != "deny" ]]; then
        echo "  WARN: $NAME - unusual permission value ($perm_val)"
        ((WARNINGS++))
      fi
    fi
  done < <(sed -n '/^permission:/,/^---$/p' <<< "$content" | tail -n +2 | head -n -1)

  # 7. Strict mode: warn if model is set
  if $STRICT_MODE && grep -q '^model:' <<< "$content"; then
    model_val=$(grep '^model:' <<< "$content" | head -1 | sed 's/.*: *//')
    echo "  WARN: $NAME - model set to $model_val (agents should be model-agnostic)"
    ((WARNINGS++))
  fi

  echo "  OK: $NAME"
done < <(find "$AGENTS_DIR" -name '*.md' ! -name 'README.md' -print0 2>/dev/null)

echo ""
echo "==> $FILES files checked, $ERRORS errors, $WARNINGS warnings"
if [[ $ERRORS -gt 0 ]]; then exit 1; fi
