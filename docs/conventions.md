# Conventions

Rules every contributor (human or agent) follows. Imported by `CLAUDE.md`.

## Naming

- **Files:** snake_case for Python.
- **Classes:** PascalCase.
- **Functions and variables:** snake_case.
- **Constants:** SCREAMING_SNAKE_CASE.
- **Private:** leading underscore. Don't double-underscore unless you actually want name mangling.
- **Graph nodes:** snake_case verb phrases — `classify_intent`, `fetch_orders`, `format_answer`.

## Imports

- Standard library first, third-party second, local last. Ruff handles ordering.
- No wildcard imports.
- Absolute imports inside `app/`. No relative imports beyond a single dot.

## Type hints

- Required on every function signature, including `__init__`, nodes, and tests.
- `from __future__ import annotations` at the top of every Python file.
- Prefer `list[X]` over `List[X]`, `X | None` over `Optional[X]`.
- `Any` only with a comment explaining why.
- LangGraph state is always typed (TypedDict or Pydantic).

## Errors

- Domain logic raises domain exceptions (subclasses of a project base).
- Routes translate domain exceptions to HTTPExceptions.
- Nodes don't catch exceptions to swallow them — let them propagate so the graph runner can record the failure in state.
- `raise ... from e` when wrapping. No swallowed tracebacks.
- Tool calls use `tenacity` for retries, not bare try/except loops.

## Logging and tracing

- `structlog` configured at app startup. JSON in prod, pretty in dev.
- `@traceable` on every LangGraph node and every tool function.
- One logger per module: `logger = structlog.get_logger(__name__)`.
- Log structured fields: `logger.info("classify_done", intent=intent, run_id=run_id)`.
- Never log secrets, tokens, or full LLM messages that might contain PII.

## Comments

- Comment *why*, not *what*.
- TODO comments include date and owner: `# TODO(gabriel, 2026-05): swap to streaming when Vertex Gemini SSE is stable`.
- Docstrings on tools (the LLM reads them) and public functions. Private helpers don't need them.

## Git

- Branch names: `<type>/<slice-id>-<short-name>` (e.g. `feat/classify-001-vertex-routing`).
- Commit messages: imperative, subject under 60 chars, body if needed.
- One slice per branch. No bundled changes.
- Rebase before merging. Don't merge main into branches.

## Tests

- Mirror source structure: `app/agents/support/nodes.py` → `tests/agents/support/test_nodes.py`.
- One assert per behavior is fine; multiple per test is also fine if related.
- Mark slow tests with `@pytest.mark.slow` so they can be excluded from inner loops.
- Never call real LLMs from tests. Always use the `fake_llm` fixture.
- Never use the real Firestore checkpointer in tests. Always use `MemorySaver`.

## Secrets

- All secrets via Secret Manager in prod, `.env.dev` in local.
- `.env.dev` is gitignored. Never check it in.
- Pydantic Settings reads them at startup, fails fast if any required secret is missing.
- A bare `os.environ` access is a smell — wrap it in Settings.
