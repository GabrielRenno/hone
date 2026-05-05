---
description: Implement a vertical slice from a plan file using strict TDD.
---

Implement the slice specified by:

$ARGUMENTS

Process:
1. Read `docs/plans/<slug>.md`. Identify the specific slice. If no slice is named, ask which one.
2. Delegate to the `test-writer` subagent to write failing tests for the slice.
3. Run the tests. Confirm they fail for the expected reason.
4. Implement the minimum code needed to make the tests pass. Use the `fastapi-patterns` skill for architectural conventions.
5. The hooks will run formatters and the type checker after each edit. The Stop hook will block you if tests are red.
6. When green, summarize what changed and which slice is now done.

Do not:
- Touch slices that weren't requested.
- Add features beyond the slice's acceptance criteria.
- Edit `migrations/` directly — use alembic.
