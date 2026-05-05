#!/usr/bin/env bash
# PreToolUse hook — blocks edits to secret/credential files.
# Exits 2 to block the tool. Stderr is shown to Claude.

set -euo pipefail

# The hook receives JSON on stdin describing the tool call.
# We extract the file_path argument.
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('tool_input',{}).get('file_path',''))")

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Patterns that should never be edited.
PATTERNS=(
  "\.env($|\..*)"
  ".*\.pem$"
  ".*\.key$"
  "secrets\..*"
  "credentials\..*"
  ".*_secret\..*"
  ".*\.p12$"
  "id_rsa.*"
)

for pattern in "${PATTERNS[@]}"; do
  if [[ "$FILE_PATH" =~ $pattern ]]; then
    echo "BLOCKED: $FILE_PATH matches secret pattern '$pattern'." >&2
    echo "If you genuinely need to edit this file, do it outside Claude Code." >&2
    exit 2
  fi
done

exit 0
