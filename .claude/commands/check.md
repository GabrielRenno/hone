---
description: Run the critic subagent over the current diff and report findings.
---

Delegate to the `critic` subagent.

The subagent will:
1. Read `git diff main...HEAD` (or `git diff` if no branch).
2. Read affected files in their full current state.
3. Surface issues in four categories: correctness, scope creep, security, architecture violations.

Pass through the subagent's findings as-is. If the subagent says nothing is wrong, say so directly. Do not pad with positives.
