---
name: pytest-tdd
description: Pytest patterns for testing LangGraph agents and the FastAPI shell. In-memory checkpointer, mocked LLM responses, deterministic test harness, async fixtures. Auto-loads when writing or running tests.
---

# Pytest TDD

Two kinds of tests: agent tests (LangGraph state and routing) and API tests (FastAPI endpoint behavior). Different shapes, same discipline.

## conftest.py layout

```python
# tests/conftest.py
import pytest
import pytest_asyncio
from httpx import AsyncClient
from langgraph.checkpoint.memory import MemorySaver
from app.main import app
from app.agents.support import build_graph_uncompiled

@pytest_asyncio.fixture
async def client() -> AsyncClient:
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac

@pytest_asyncio.fixture
def graph():
    """A graph compiled with an in-memory checkpointer. Fresh per test."""
    return build_graph_uncompiled().compile(checkpointer=MemorySaver())

@pytest.fixture
def fake_llm(monkeypatch):
    """Replace the chat model with a deterministic stub."""
    from app.tools import model_router
    responses = []

    def push(reply: str):
        responses.append(reply)

    class FakeModel:
        async def ainvoke(self, messages):
            return AIMessage(content=responses.pop(0))

    monkeypatch.setattr(model_router, "anthropic_chat_model", lambda **_: FakeModel())
    return push  # tests call push("first reply"), push("second reply")
```

## pyproject.toml settings

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
```

## Testing nodes (unit)

```python
async def test_classify_intent_returns_tool_call(fake_llm):
    fake_llm("tool_call")
    state = AgentState(user_id="u1", run_id="r1", messages=[HumanMessage("get my orders")])
    result = await classify_intent(state)
    assert result["intent"] == "tool_call"
```

Test nodes in isolation with mocked LLM responses. No graph involved.

## Testing graphs (integration)

```python
async def test_graph_routes_tool_call_path(graph, fake_llm):
    fake_llm("tool_call")           # classify says: tool
    fake_llm("Here are 3 orders.")  # final answer

    config = {"configurable": {"thread_id": "test-run-1"}}
    result = await graph.ainvoke(
        {"messages": [HumanMessage("get my orders")], "user_id": "u1", "run_id": "test-run-1"},
        config=config,
    )

    assert result["final_answer"] == "Here are 3 orders."
    assert len(result["tool_results"]) == 1
```

Graph tests assert on final state, not LLM response strings (which you control via fake_llm anyway).

## Testing edges

```python
def test_route_after_classify_routes_to_tool():
    state = {"intent": "tool_call"}
    assert route_after_classify(state) == "execute_tool"

def test_route_after_classify_ends_on_unknown():
    state = {"intent": "garbage"}
    assert route_after_classify(state) == "end"
```

Edges are pure functions. Trivial to test. Cover every branch.

## Testing the API layer

```python
async def test_create_run_returns_200(client: AsyncClient, fake_llm):
    fake_llm("answer")
    fake_llm("Hello!")
    response = await client.post("/runs", json={"client_id": "c1", "message": "hi"})
    assert response.status_code == 200
    body = response.json()
    assert body["final_answer"] == "Hello!"
```

API tests use the test client and the same fake_llm fixture. The graph compiles fresh per test.

## Testing tool functions

```python
async def test_search_orders_returns_results(monkeypatch):
    async def fake_search(user_id, query):
        return [{"id": "o1"}]
    monkeypatch.setattr("app.tools.orders_service.search", fake_search)

    result = await search_orders.ainvoke({"user_id": "u1", "query": "x"})
    assert len(result) == 1
```

Tools are functions with side effects. Mock the side effect, assert on the output.

## Testing checkpointers / async runs

For Pub/Sub push handlers, simulate the envelope:

```python
async def test_internal_execute_runs_graph(client, fake_llm):
    fake_llm("answer")
    fake_llm("done")
    envelope = {"message": {"data": base64.b64encode(json.dumps({
        "run_id": "r-1",
        "input": {"messages": [...], "user_id": "u1"},
    }).encode()).decode()}}

    response = await client.post("/internal/runs/execute", json=envelope)
    assert response.status_code == 204
```

## Coverage rules

- Every test asserts on at least one specific behavior. `assert response.status_code == 200` alone is not enough.
- Every node has a happy-path test and at least one edge case (LLM returns unexpected output, tool errors, missing state field).
- Every conditional edge has a test per branch.
- API tests cover: happy path, validation error (422), auth missing (401), not found (404).

## Speed rules

- Use `MemorySaver` for graph tests, never the Firestore checkpointer.
- Use `pytest -k <pattern>` for tight inner loops. Full suite runs on commit.
- Don't hit real LLMs in tests, ever. The fake_llm fixture is the contract.

## Don't

- Don't write integration tests against real LangSmith. Use the fake.
- Don't leave a `print` in tests. Use `pytest -s` to see output, but commit clean.
- Don't share `MemorySaver` across tests. Fresh per test.
