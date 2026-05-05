# Task: Async Run Endpoint (Reference Task)

Reference task for the API + Pub/Sub layer. Builds an endpoint that kicks off an async agent run.

## Setup
- git checkout starting-fixture
- uv sync

## Prompt
Implement a POST /runs/async endpoint that:
- Accepts a Pydantic v2 RunCreate (client_id, message, optional run_id).
- Generates a run_id if none provided.
- Writes initial run state to Firestore (collection: agent_runs, doc_id: run_id, status: queued).
- Publishes a message to Pub/Sub topic `agent-runs` with the run_id and input payload.
- Returns 202 with a RunAccepted response (run_id, status_url).

The Pub/Sub publisher and Firestore client must be injected via FastAPI Depends — never instantiated inside the route.

Follow TDD strictly. Use the Pub/Sub emulator and Firestore emulator in tests via the existing fixtures.

## Acceptance
Commands that must exit 0:
- pytest tests/api/test_runs.py -q
- ruff check .
- mypy --strict app/

## Rubric overrides
- Must use Pydantic v2 (model_config = ConfigDict, not class Config).
- Must NOT call Firestore or Pub/Sub directly inside the route — must use injected dependencies.
- Must return 202, not 200 (it's async).
- Tests must mock the Pub/Sub publisher and assert on what was published.
- Must NOT include any business logic in the route — purely orchestration.
