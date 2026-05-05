#!/usr/bin/env bash
# Stop hook — refuses to let Claude end the turn while tests are red.
# Exits 2 to force continuation. Output goes to Claude.

set -euo pipefail

# Skip if no tests directory or no pytest available.
if [[ ! -d "tests" ]] && [[ ! -d "test" ]]; then
  exit 0
fi

if ! command -v pytest &> /dev/null; then
  exit 0
fi

# Try to scope to changed files via git, fall back to full suite if that fails.
CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep -E "\.py$" || true)

if [[ -z "$CHANGED" ]]; then
  # Nothing changed — let the turn end.
  exit 0
fi

# Derive a -k pattern from changed test or source filenames.
KEYWORDS=$(echo "$CHANGED" | xargs -n1 basename 2>/dev/null | sed 's/\.py$//' | sed 's/^test_//' | sort -u | tr '\n' ' ' | sed 's/ /\\|/g; s/\\|$//')

if [[ -z "$KEYWORDS" ]]; then
  exit 0
fi

OUTPUT=$(pytest -k "$KEYWORDS" --maxfail=3 -q 2>&1 || true)

if echo "$OUTPUT" | grep -qE "(failed|error)"; then
  echo "Tests are failing. You must fix them before stopping." >&2
  echo "$OUTPUT" | tail -50 >&2
  exit 2
fi

exit 0
