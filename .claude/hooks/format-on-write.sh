#!/usr/bin/env bash
# PostToolUse hook — formats Python files after edits.
# Async: true in settings.json, so this runs without blocking.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('file_path',''))")

# Only run on Python files inside the project.
if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ \.py$ ]]; then
  exit 0
fi

if ! command -v ruff &> /dev/null; then
  exit 0
fi

ruff format "$FILE_PATH" 2>&1 | head -5 || true
ruff check --fix --unsafe-fixes "$FILE_PATH" 2>&1 | head -10 || true

exit 0
