---
name: langgraph-patterns
description: LangGraph conventions for agent design — state schemas, nodes, conditional edges, checkpointers, subgraphs. Auto-loads when working on agents, graphs, nodes, or anything under app/agents/.
---

# LangGraph Patterns

LangGraph is the default agent framework. State + nodes + edges. Nothing else.

## State

State is a Pydantic model or TypedDict. Every field has a type. Mutable fields default to `None` or `[]`. State is the contract between nodes — keep it explicit.

```python
from typing import TypedDict, Annotated
from langgraph.graph.message import add_messages
from langchain_core.messages import BaseMessage

class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    user_id: str
    run_id: str
    tool_results: list[dict]
    final_answer: str | None
```

Use `Annotated[..., add_messages]` for message lists — LangGraph appends instead of overwriting.

For complex state, prefer Pydantic v2:

```python
from pydantic import BaseModel, Field

class AgentState(BaseModel):
    user_id: str
    run_id: str
    messages: list[BaseMessage] = Field(default_factory=list)
    tool_results: list[ToolResult] = Field(default_factory=list)
    final_answer: str | None = None

    model_config = {"arbitrary_types_allowed": True}
```

## Nodes

A node is a function: `state → partial_state`. Returns a dict with only the fields it changed.

```python
from langsmith import traceable

@traceable
async def classify_intent(state: AgentState) -> dict:
    last_msg = state["messages"][-1].content
    intent = await anthropic_client.classify(last_msg)
    return {"intent": intent}
```

Rules:
- Async by default. Long-running nodes block the worker otherwise.
- `@traceable` always — non-negotiable for LangSmith visibility.
- One responsibility per node. If a node does two things, split it.
- Tools are called from nodes via `tools/` modules, never SDK-direct.

## Edges

Conditional edges route based on state. Pure functions: `state → next_node_name`.

```python
def route_after_classify(state: AgentState) -> str:
    if state["intent"] == "tool_call":
        return "execute_tool"
    if state["intent"] == "answer":
        return "format_answer"
    return "end"
```

Never put side effects in an edge. Routing only.

## Building the graph

```python
from langgraph.graph import StateGraph, END

def build_graph():
    g = StateGraph(AgentState)
    g.add_node("classify", classify_intent)
    g.add_node("execute_tool", execute_tool)
    g.add_node("format_answer", format_answer)

    g.set_entry_point("classify")
    g.add_conditional_edges("classify", route_after_classify, {
        "execute_tool": "execute_tool",
        "format_answer": "format_answer",
        "end": END,
    })
    g.add_edge("execute_tool", "classify")  # loop back
    g.add_edge("format_answer", END)

    return g.compile(checkpointer=firestore_checkpointer())
```

The compiled graph is what gets invoked. Build it once at app startup, not per request.

## Checkpointers

In production, every graph compiles with a Firestore checkpointer (see `gcp-state-and-events` skill). For tests, use `MemorySaver`:

```python
from langgraph.checkpoint.memory import MemorySaver
graph = build_graph_uncompiled().compile(checkpointer=MemorySaver())
```

## Invocation

```python
config = {"configurable": {"thread_id": run_id}}
result = await graph.ainvoke({"messages": [HumanMessage(content=prompt)]}, config=config)
```

`thread_id` is what the checkpointer keys on. Use the run_id, never the user_id (multiple runs per user).

For streaming:

```python
async for event in graph.astream({"messages": [...]}, config=config):
    # event is {"node_name": partial_state}
    yield format_sse(event)
```

## Tool calling

Use the LangChain `@tool` decorator for tools the agent can choose. Bind them to the model in a node:

```python
from langchain_core.tools import tool

@tool
async def search_docs(query: str) -> str:
    """Search internal documentation. Use when user asks about how something works."""
    return await internal_docs_client.search(query)

async def call_model(state: AgentState) -> dict:
    model = anthropic_chat_model().bind_tools([search_docs, fetch_user_data])
    response = await model.ainvoke(state["messages"])
    return {"messages": [response]}
```

Tool docstrings ARE the prompt for the model — write them as carefully as you'd write any LLM prompt.

## Subgraphs

When a chunk of logic is reusable across agents, build it as its own graph and embed it as a node:

```python
def build_research_subgraph():
    g = StateGraph(ResearchState)
    # ... build ...
    return g.compile()

research_graph = build_research_subgraph()

# In the parent graph:
g.add_node("research", research_graph)
```

State translation between parent and subgraph happens via input/output schemas. Don't share mutable state across graph boundaries.

## Anti-patterns

- **Stateful module-level globals.** Workers restart. Anything you stash in a module variable is gone.
- **Sync DB calls in nodes.** Blocks the event loop. Use async clients.
- **Edges that compute things.** Edges only route. Computation goes in a node.
- **One mega-node.** If a node is over ~30 lines, it's doing too much. Split.
- **Untyped state.** Don't use bare `dict` as state. You'll regret it on day three.
