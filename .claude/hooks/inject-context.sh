#!/usr/bin/env bash
# UserPromptSubmit hook — injects lightweight git context at the start of each prompt.
# Adds branch name, last 3 commits, and any active plan file.

set -euo pipefail

# Trigger auto-compact at 50% context usage (~100k tokens) to prevent quality degradation.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50

if ! command -v git &> /dev/null; then
  exit 0
fi

if ! git rev-parse --git-dir &> /dev/null; then
  exit 0
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
COMMITS=$(git log --oneline -3 2>/dev/null || echo "")
PLANS=""

if [[ -d "docs/plans" ]]; then
  RECENT=$(ls -t docs/plans/*.md 2>/dev/null | head -1 || true)
  if [[ -n "$RECENT" ]]; then
    PLANS="Active plan file: $RECENT"
  fi
fi

CHECKPOINT=""
if [[ -f ".claude/checkpoints/current.md" ]]; then
  CHECKPOINT=$(cat .claude/checkpoints/current.md 2>/dev/null || true)
fi

# Output goes to stdout and is appended to the user's prompt as context.
cat << CTX
<git-context>
Branch: $BRANCH
Recent commits:
$COMMITS
$PLANS
</git-context>
CTX

if [[ -n "$CHECKPOINT" ]]; then
  cat << CKPT
<session-checkpoint>
$CHECKPOINT
</session-checkpoint>
CKPT
fi

exit 0
