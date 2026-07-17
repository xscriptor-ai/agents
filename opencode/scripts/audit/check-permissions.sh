#!/usr/bin/env bash
# check-permissions.sh - Audit agent permissions for security risks.
# Usage: ./audit/check-permissions.sh [--agents PATH] [--risk-only]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/agents"
RISK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agents) AGENTS_DIR="$2"; shift 2 ;;
    --risk-only) RISK_ONLY=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

HIGH_RISK=0
MEDIUM_RISK=0
WARNINGS=0
MISSING_DESC=0
MISSING_COLOR=0

while IFS= read -r -d '' file; do
  NAME=$(basename "$file")
  content=$(<"$file")

  HAS_EDIT=false
  HAS_BASH=false

  if grep -qi 'edit: allow' <<< "$content"; then
    HAS_EDIT=true
    ((HIGH_RISK++))
    echo "  HIGH RISK: $NAME - edit: allow"
  fi

  if grep -qi 'bash: allow' <<< "$content"; then
    HAS_BASH=true
    ((MEDIUM_RISK++))
    $RISK_ONLY || echo "  MEDIUM: $NAME - bash: allow"
  fi

  if $HAS_EDIT && $HAS_BASH; then
    ((WARNINGS++))
    echo "  WARNING: $NAME - both edit AND bash are set to allow"
  fi

  if ! grep -q '^description:' <<< "$content"; then
    ((MISSING_DESC++))
    echo "  MISSING: $NAME - no description"
  fi

  if ! grep -q '^color:' <<< "$content"; then
    ((MISSING_COLOR++))
    echo "  NO COLOR: $NAME - no color set"
  fi
done < <(find "$AGENTS_DIR" -name '*.md' ! -name 'README.md' -print0 2>/dev/null)

echo ""
echo "==> Audit complete"
echo "    High risk (edit: allow): $HIGH_RISK"
echo "    Medium risk (bash: allow): $MEDIUM_RISK"
echo "    Edit + bash combined: $WARNINGS"
echo "    Missing description: $MISSING_DESC"
echo "    No color: $MISSING_COLOR"

if [[ $HIGH_RISK -gt 0 || $MEDIUM_RISK -gt 0 ]]; then
  echo ""
  echo "Note: Some agents intentionally need elevated permissions (refactor-agent, db-migrator)."
  echo "Review each flagged agent individually."
fi
