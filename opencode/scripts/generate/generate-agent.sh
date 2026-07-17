#!/usr/bin/env bash
# generate-agent.sh - Interactive OpenCode agent generator.
# Usage: ./generate/generate-agent.sh [--output PATH]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/agents/custom"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

mkdir -p "$OUTPUT_DIR"

echo "==> OpenCode Agent Generator"
echo ""

read -rp "Agent name (filename, no spaces): " NAME
read -rp "Description (one line): " DESC
read -rp "Mode [subagent/primary/all] (default: subagent): " MODE
MODE="${MODE:-subagent}"
read -rp "Temperature [0.0-1.0] (default: 0.2): " TEMP
TEMP="${TEMP:-0.2}"
read -rp "Color [#RRGGBB or theme token] (default: primary): " COLOR
COLOR="${COLOR:-primary}"
read -rp "Model [provider/model or empty for model-agnostic]: " MODEL

echo ""
echo "Permissions (allow / ask / deny):"
read -rp "  edit: " PERM_EDIT
read -rp "  bash: " PERM_BASH
read -rp "  glob: " PERM_GLOB
read -rp "  grep: " PERM_GREP
read -rp "  read: " PERM_READ
read -rp "  list: " PERM_LIST
read -rp "  webfetch: " PERM_WEBFETCH

FILE="$OUTPUT_DIR/$NAME.md"
cat > "$FILE" << FRONTMATTER
---
description: ${DESC}
mode: ${MODE}
temperature: ${TEMP}
color: "${COLOR}"
FRONTMATTER

if [[ -n "$MODEL" ]]; then
  echo "model: ${MODEL}" >> "$FILE"
fi

cat >> "$FILE" << PERMS
permission:
  edit: ${PERM_EDIT:-ask}
  bash: ${PERM_BASH:-ask}
  glob: ${PERM_GLOB:-ask}
  grep: ${PERM_GREP:-ask}
  read: ${PERM_READ:-ask}
  list: ${PERM_LIST:-ask}
  webfetch: ${PERM_WEBFETCH:-ask}
PERMS

cat >> "$FILE" << 'BODY'
---

You are a ${NAME} specialist.

## Your Role

Describe what this agent does and when to use it.

## Responsibilities

- List key responsibilities
- Include specific behaviors
- Define boundaries

## Rules

1. Rule one
2. Rule two
3. Rule three

## Checklist

- [ ] Check item one
- [ ] Check item two
BODY

echo ""
echo "==> Generated: $FILE"
echo "Edit the body section to add specific instructions."
