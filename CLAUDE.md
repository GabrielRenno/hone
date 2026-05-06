# Project: <project-name>

## Stack
- Python 3.12, LangGraph, LangChain, LangSmith
- FastAPI as the thin API layer that wraps agents
- Pydantic v2 for state schemas and external IO
- Firestore for agent state (default checkpointer)
- Pub/Sub for async agent triggers
- Vertex AI for non-Anthropic models, Anthropic API direct for Claude
- Cloud Run for serving, Secret Manager for credentials, Cloud Build for CI
- pytest + httpx.AsyncClient for tests
- Ruff for lint and format, mypy --strict for types

## Architecture
Three layers:
- **API layer** (FastAPI) — thin. Validates input, hands off to agent layer.
- **Agent layer** (LangGraph) — graph state + nodes + conditional edges. The brain.
- **Service layer** — tools and external integrations: Firestore, Pub/Sub, Vertex, Anthropic, internal APIs.

Full architecture: @docs/architecture.md

## Non-negotiables
- TDD: write the failing test first, always
- Every LangGraph node has a Pydantic input + output schema
- Every node is `@traceable` for LangSmith — no untraced agent code in production
- Secrets only via Secret Manager, never `.env` in production
- Firestore for agent state — workers must be stateless, restartable mid-run
- No business logic in routers — they call the graph and return
- Type hints required on every function signature

## Conventions
@docs/conventions.md

## Workflow
- Plan files live in `docs/plans/<slug>.md`
- Vertical slices: each must be independently shippable and reversible
- Use `/clear-and-go <slug>` between slices to keep context lean
- Run `/check` before considering a slice done
- Run `/score` on substantive features

## Tools you have
- `gh` CLI for GitHub
- `gcloud` CLI for GCP (Cloud Run deploys, Secret Manager, Pub/Sub)
- `docker compose` for the dev stack
- `pytest -k <pattern>` for targeted runs

## When you don't know something
Use the `explorer` subagent for repo navigation. Don't grep blindly from main context.

## Compact Instructions
When compacting this conversation, always preserve:
- The current slice being worked on and its acceptance criteria
- All decisions made (architecture choices, trade-offs, rejected alternatives) and their reasoning
- File paths that have been modified or are relevant to the current task
- Current test state (what's passing, what's failing, what's left to write)
- Any user preferences or corrections expressed during this session
- The checkpoint file path if one exists (read it for full state)

Discard:
- Raw file contents that were read for exploration (the files still exist on disk)
- Verbose tool output (test logs, git diffs, grep results)
- Intermediate reasoning that led to decisions already captured above
