---
name: fastapi-patterns
description: FastAPI as the thin API layer wrapping LangGraph agents. Routes validate input and invoke graphs, nothing more. Auto-loads when working on routes, request/response schemas, or HTTP-layer concerns.
---

# FastAPI Patterns

FastAPI is the thin shell around the agent layer. It validates HTTP, calls the graph, returns the result. No business logic.

## Layer responsibilities

```
Router  → validates input via Pydantic, invokes the graph, returns response
Graph   → does the work (see langgraph-patterns)
Tools   → external integrations (see gcp-state-and-events, langchain-utilities)
```

A route that imports a node directly is a smell. A route that calls Firestore directly is a smell. The route invokes the graph and gets out of the way.

## Synchronous run pattern

For interactive runs that complete in under ~60s:

```python
from fastapi import APIRouter, Depends
from app.schemas.runs import RunCreate, RunResult
from app.agents.support import build_graph

router = APIRouter(prefix="/runs", tags=["runs"])
graph = build_graph()  # built once at import

@router.post("", response_model=RunResult, status_code=200)
async def create_run(data: RunCreate, user_id: str = Depends(current_user_id)) -> RunResult:
    config = {
        "configurable": {"thread_id": data.run_id or new_run_id()},
        "metadata": {"user_id": user_id, "client": data.client_id},
    }
    output = await graph.ainvoke(data.to_input_state(user_id), config=config)
    return RunResult.from_state(output)
```

The route does four things: build config, call graph, format response, return. That's it.

## Async run pattern

For long-running agents (over ~60s, or anything that touches a slow tool), publish to Pub/Sub and return 202:

```python
@router.post("/async", status_code=202, response_model=RunAccepted)
async def create_async_run(
    data: RunCreate,
    publisher: RunPublisher = Depends(get_publisher),
) -> RunAccepted:
    run_id = new_run_id()
    await write_initial_state(run_id, data, status="queued")
    await publisher.publish(run_id, payload=data.model_dump())
    return RunAccepted(run_id=run_id, status_url=f"/runs/{run_id}")
```

The execution endpoint is a Pub/Sub push handler — see `gcp-state-and-events`.

## Streaming pattern

For agents that emit tokens or intermediate state:

```python
from fastapi.responses import StreamingResponse

@router.post("/stream")
async def stream_run(data: RunCreate, user_id: str = Depends(current_user_id)):
    config = {"configurable": {"thread_id": data.run_id}, "metadata": {"user_id": user_id}}

    async def event_stream():
        async for event in graph.astream(data.to_input_state(user_id), config=config):
            for node_name, partial in event.items():
                yield f"event: {node_name}\ndata: {json.dumps(partial, default=str)}\n\n"

    return StreamingResponse(event_stream(), media_type="text/event-stream")
```

## Schemas

Three schemas per resource, even for thin routes:

```python
# app/schemas/runs.py
class RunCreate(BaseModel):
    client_id: str
    message: str
    run_id: str | None = None  # optional client-provided idempotency key

    def to_input_state(self, user_id: str) -> AgentState:
        return AgentState(
            user_id=user_id,
            run_id=self.run_id or new_run_id(),
            messages=[HumanMessage(content=self.message)],
        )

class RunAccepted(BaseModel):
    run_id: str
    status_url: str

class RunResult(BaseModel):
    run_id: str
    final_answer: str
    tool_calls: list[ToolCall]

    @classmethod
    def from_state(cls, state: AgentState) -> "RunResult":
        return cls(
            run_id=state["run_id"],
            final_answer=state["final_answer"],
            tool_calls=state.get("tool_results", []),
        )
```

`to_input_state` and `from_state` keep the graph's state shape isolated from the API contract. Change the graph internals without breaking clients.

## Dependency injection

```python
async def get_publisher() -> RunPublisher:
    return RunPublisher(project=settings.gcp_project, topic="agent-runs")

async def get_firestore_client() -> firestore_v1.AsyncClient:
    return firestore_v1.AsyncClient(project=settings.gcp_project)
```

Don't instantiate clients per-request. Cache them at module level or as FastAPI lifespan resources.

## Auth

Routes that need auth use a `Depends(current_user_id)` (or similar) that validates JWT/IAM/whatever. Auth check NEVER happens inside a graph — by the time the graph is invoked, the user is already authenticated.

## What's not in this layer

- LLM calls
- Firestore writes (other than the queue write for async runs)
- Tool selection logic
- Retry policies for tool calls
- Any business rule

Push everything below to the agent or service layer.
