#!/usr/bin/env bash
# PreToolUse hook — blocks edits to protected paths (migrations, vendored code, .git).
# Exits 2 to block. Stderr is shown to Claude.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('file_path',''))")

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Paths that require explicit human action, not Claude edits.
PROTECTED=(
  "^migrations/"
  "/migrations/"
  "^\.git/"
  "/\.git/"
  "^node_modules/"
  "/node_modules/"
  "^\.venv/"
  "/\.venv/"
  "^dist/"
  "^build/"
)

for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" =~ $pattern ]]; then
    echo "BLOCKED: $FILE_PATH is in a protected path ($pattern)." >&2
    echo "Migrations: use 'alembic revision --autogenerate' instead." >&2
    echo "Vendored or generated code: edit the source, not the output." >&2
    exit 2
  fi
done

exit 0
