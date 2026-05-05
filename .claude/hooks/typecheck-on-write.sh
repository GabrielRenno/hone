#!/usr/bin/env bash
# PostToolUse hook — runs mypy on the edited file.
# Surfaces type errors immediately so Claude fixes them in-context.
# Does not block — exit 0 always. Output goes to stderr for Claude to read.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('file_path',''))")

if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ \.py$ ]]; then
  exit 0
fi

# Skip tests directory — types there are looser by convention.
if [[ "$FILE_PATH" =~ ^tests/ ]] || [[ "$FILE_PATH" =~ /tests/ ]]; then
  exit 0
fi

if ! command -v mypy &> /dev/null; then
  exit 0
fi

OUTPUT=$(mypy --strict --no-error-summary "$FILE_PATH" 2>&1 || true)

if [[ -n "$OUTPUT" ]] && echo "$OUTPUT" | grep -q "error:"; then
  echo "mypy found type errors in $FILE_PATH:" >&2
  echo "$OUTPUT" >&2
fi

exit 0
