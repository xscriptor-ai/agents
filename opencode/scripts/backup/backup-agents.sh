#!/usr/bin/env bash
# backup-agents.sh - Backup installed OpenCode agents.
# Usage: ./backup/backup-agents.sh [--source PATH] [--dest PATH]
set -euo pipefail

SOURCE="${HOME}/.config/opencode/agents"
DEST="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

if [[ ! -d "$SOURCE" ]]; then
  echo "Source directory not found: $SOURCE"
  echo "Nothing to back up."
  exit 0
fi

TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
OUTFILE="opencode-agents-${TIMESTAMP}.tar.gz"

tar -czf "${DEST}/${OUTFILE}" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")"

echo "==> Backup created: ${DEST}/${OUTFILE}"
echo "    Size: $(du -h "${DEST}/${OUTFILE}" | cut -f1)"
echo "    Agents: $(find "$SOURCE" -name '*.md' | wc -l | tr -d ' ')"
