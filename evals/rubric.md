# Eval Rubric

The default behavioral checks applied to every golden task. Tasks may add more in their `## Rubric overrides` section.

## Process discipline

1. **Tests written before implementation.** Verifiable from git log: the first commit on the branch must add or modify a test file before any source file change.

2. **Stayed within slice scope.** The diff should only touch files relevant to the slice. Stray edits to unrelated files fail this item.

3. **No hook bypass.** No commits with `--no-verify`. No edits inside `migrations/`, `.git/`, `.env*`, or other protected paths.

## Output quality

4. **No over-engineering.** No new abstractions for a single caller. No configuration options that weren't requested. No "while I'm in here" refactors.

5. **Architecture respected.** Routes invoke graphs, not nodes directly. No business logic in route handlers. Tools (Firestore, Pub/Sub, LLM clients) are called from nodes via `tools/` modules, never SDK-direct.

6. **Pydantic models used at boundaries.** All external IO (HTTP, queues, external APIs) goes through Pydantic v2 models.

## Verification gates

7. **`pytest` passes.** All tests on the affected branch.

8. **`ruff check .` passes** with no errors.

9. **`mypy --strict app/` passes** with no errors.

10. **Coverage rule.** Each new test asserts on at least one specific behavior beyond status code.

## Scoring

Each item is pass / fail / partial. The eval runner records the verdict per item and per task. A score of 8/10 or better is a green run.
