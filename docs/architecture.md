# Architecture

Three layers. Each has one job.

```
┌──────────────────────────────────────────────────┐
│   API Layer (FastAPI)                            │
│   Thin. Validates HTTP. Hands off to graph.      │
├──────────────────────────────────────────────────┤
│   Agent Layer (LangGraph)                        │
│   State + nodes + conditional edges.             │
│   Where the actual reasoning happens.            │
├──────────────────────────────────────────────────┤
│   Service Layer                                  │
│   Tools the graph calls: Firestore, Pub/Sub,     │
│   Vertex, Anthropic, internal APIs.              │
└──────────────────────────────────────────────────┘
```

## File layout

```
app/
├── api/
│   ├── routes/
│   │   └── runs.py              # POST /runs, GET /runs/{id}
│   └── deps.py                   # FastAPI dependencies
├── agents/
│   └── <agent_name>/
│       ├── graph.py              # build_graph() returns compiled StateGraph
│       ├── state.py              # AgentState (Pydantic / TypedDict)
│       ├── nodes.py              # node functions: state → state
│       ├── edges.py              # conditional routing
│       └── prompts.py            # prompt templates
├── tools/
│   ├── firestore_state.py        # checkpointer
│   ├── pubsub.py                 # publishers, subscriber handlers
│   ├── vertex.py                 # non-Anthropic model client
│   └── anthropic_client.py       # Claude
├── schemas/                      # Pydantic models for IO
├── core/
│   ├── config.py                 # Settings via Pydantic + Secret Manager
│   ├── tracing.py                # LangSmith setup
│   └── logging.py
└── main.py
```

## Flow rules

- **Routes call graphs, not nodes.** A route invokes the compiled graph with an input. It does not call individual nodes.
- **Nodes are pure-ish.** Each node takes state, calls services, returns state. No side effects beyond logging and traced tool calls.
- **Tools live in `tools/`.** A node that wants to read Firestore calls a tools function, not the SDK directly. This is what makes nodes mockable.
- **State is Pydantic or TypedDict.** Every field has a type. Optional fields default to `None`. State is the contract between nodes.

## What goes where

| Logic | Lives in |
|---|---|
| HTTP validation | Pydantic request schema, route handler |
| Auth check | Route dependency |
| Agent reasoning, tool selection | Node function |
| Routing between nodes | Edge function |
| LLM call | `tools/anthropic_client.py` or `tools/vertex.py` |
| State persistence | LangGraph checkpointer (Firestore) |
| Async dispatch ("kick off this agent") | `tools/pubsub.py` publisher |
| Side effects on a schedule | Pub/Sub push → Cloud Run handler |

## Async flow

For long-running or fire-and-forget agent runs:

```
Client → POST /runs → publishes to Pub/Sub → returns 202 with run_id
                                ↓
                  Pub/Sub push → /runs/internal/execute
                                ↓
                  Builds graph, runs to completion, writes state to Firestore
                                ↓
                  Optional: Pub/Sub publish → notification topic
```

For interactive runs, route handler invokes graph synchronously and streams the result.

## Why Firestore for state

LangGraph checkpointers persist state at every step. With Firestore:
- Workers are stateless. A Cloud Run instance can die mid-run; another picks up from the last checkpoint.
- State is queryable. You can list active runs, find stuck runs, replay from any point.
- It's pay-per-read, which fits the burst pattern of agent traffic.

If your agent needs relational data (joins, aggregations, transactions), use Postgres for *that* data — but keep agent state in Firestore.

## When to add a new layer

You probably don't need to. Three layers handle the entire domain.

If you're tempted to add a "service abstraction" layer between agent and tools — resist it. Tools functions are the abstraction. If a tool grows too big, split it into multiple tool files.
