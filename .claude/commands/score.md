---
description: Score the current diff against the eval rubric.
---

Read `evals/rubric.md`. For each rubric item, check the current state of the diff and the recent git history.

Output a checklist:

```
- [x] Test file created before implementation file (git log confirms)
- [x] Stayed within slice scope
- [ ] Did not over-engineer — adds Optional config flag for retry count that wasn't required
- [x] Did not touch protected paths
- [x] pytest, ruff, mypy --strict all pass
```

For each unchecked item, explain in one sentence what specifically was wrong.

Save the report to `evals/runs/manual-<timestamp>.md`.
