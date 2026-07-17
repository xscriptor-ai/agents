#!/usr/bin/env bash
# diff-agents.sh - Compare installed agents against repository agents.
# Usage: ./diff/diff-agents.sh [--local PATH] [--repo PATH] [--missing-only]
set -euo pipefail

LOCAL="${HOME}/.config/opencode/agents"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/agents"
MISSING_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local) LOCAL="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --missing-only) MISSING_ONLY=true; shift ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

echo "==> Comparing local ($LOCAL) vs repo ($REPO)"
echo ""

# Agents in local but not in repo
echo "--- Local-only agents (not in repo):"
LOCAL_ONLY=0
while IFS= read -r -d '' f; do
  name=$(basename "$f")
  if [[ ! -f "$REPO/$name" ]]; then
    echo "  - $name"
    ((LOCAL_ONLY++))
  fi
done < <(find "$LOCAL" -name '*.md' -print0 2>/dev/null || true)

# Agents in repo but not in local
echo ""
echo "--- Repo-only agents (not installed):"
REPO_ONLY=0
while IFS= read -r -d '' f; do
  name=$(basename "$f")
  if [[ ! -f "$LOCAL/$name" ]]; then
    echo "  - $name"
    ((REPO_ONLY++))
  fi
done < <(find "$REPO" -name '*.md' ! -name 'README.md' -print0 2>/dev/null)

# Size differences
if ! $MISSING_ONLY; then
  echo ""
  echo "--- Modified agents (size differs):"
  MODIFIED=0
  while IFS= read -r -d '' f; do
    name=$(basename "$f")
    local_f="$LOCAL/$name"
    if [[ -f "$local_f" ]]; then
      repo_size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
      local_size=$(stat -f%z "$local_f" 2>/dev/null || stat -c%s "$local_f" 2>/dev/null)
      if [[ "$repo_size" != "$local_size" ]]; then
        echo "  - $name (repo: ${repo_size}B, local: ${local_size}B)"
        ((MODIFIED++))
      fi
    fi
  done < <(find "$REPO" -name '*.md' ! -name 'README.md' -print0 2>/dev/null)
fi

echo ""
echo "==> Summary: $LOCAL_ONLY local-only, $REPO_ONLY pending install, ${MODIFIED:-0} modified"
