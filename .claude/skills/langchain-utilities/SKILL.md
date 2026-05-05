---
name: langchain-utilities
description: The sharp tools from LangChain we actually use — chat models, output parsers, prompt templates, tool decorators, model routing across Anthropic and Vertex. Auto-loads when working with LangChain primitives outside of LangGraph nodes.
---

# LangChain Utilities

LangChain is a toolbox. Use the sharp tools, ignore the rest.

## Chat models

```python
from langchain_anthropic import ChatAnthropic
from langchain_google_vertexai import ChatVertexAI

def anthropic_chat_model(model: str = "claude-sonnet-4-6") -> ChatAnthropic:
    return ChatAnthropic(
        model=model,
        anthropic_api_key=settings.anthropic_api_key,
        max_tokens=4096,
        temperature=0,
    )

def vertex_chat_model(model: str = "gemini-2.5-pro") -> ChatVertexAI:
    return ChatVertexAI(
        model=model,
        project=settings.gcp_project,
        location="us-central1",
        max_output_tokens=4096,
    )
```

Wrap construction in a function so model selection is one place to change.

## Model routing

For heterogeneous routing (cheap model for classification, smart model for synthesis):

```python
def model_for_task(task: str) -> BaseChatModel:
    match task:
        case "classify" | "extract":
            return vertex_chat_model("gemini-2.5-flash")
        case "reason" | "synthesize":
            return anthropic_chat_model("claude-sonnet-4-6")
        case "complex_reasoning":
            return anthropic_chat_model("claude-opus-4-6")
```

Centralize the routing in `tools/model_router.py`. Nodes call `model_for_task("classify")`, never instantiate models directly.

## Structured output

Use Pydantic for any LLM output you'll act on programmatically.

```python
from pydantic import BaseModel, Field

class Classification(BaseModel):
    intent: str = Field(description="One of: tool_call, answer, clarify")
    confidence: float = Field(ge=0, le=1)
    reasoning: str

structured = anthropic_chat_model().with_structured_output(Classification)
result: Classification = await structured.ainvoke(prompt)
```

Don't parse JSON from text. Use `with_structured_output`. It uses tool-calling under the hood and is reliable.

## Output parsers

Only when `with_structured_output` doesn't fit (streaming, weird formats). Otherwise skip.

```python
from langchain_core.output_parsers import PydanticOutputParser

parser = PydanticOutputParser(pydantic_object=Classification)
chain = prompt | model | parser
```

## Prompts

Prompt templates live in `prompts.py` next to the agent. Use ChatPromptTemplate, never f-strings:

```python
from langchain_core.prompts import ChatPromptTemplate

CLASSIFY_PROMPT = ChatPromptTemplate.from_messages([
    ("system", "You classify user intents. Output one of: tool_call, answer, clarify."),
    ("human", "{message}"),
])
```

Why not f-strings: ChatPromptTemplate handles escaping, partials, and chat-format conversion. f-strings break with curly braces in user input.

## Tools

```python
from langchain_core.tools import tool

@tool
async def search_orders(user_id: str, query: str) -> list[dict]:
    """Search a user's order history.

    Use when the user asks about past orders, deliveries, or refunds.
    """
    return await orders_service.search(user_id=user_id, query=query)
```

Tool docstrings are the prompt for the model. Write them like you'd write any prompt.

## LCEL — when to use it

LangChain Expression Language (`prompt | model | parser`) is fine for linear chains:

```python
classify_chain = (
    CLASSIFY_PROMPT
    | anthropic_chat_model()
    | PydanticOutputParser(pydantic_object=Classification)
)
```

Don't force LCEL where it doesn't fit. For anything with branching, retries, or state — that's LangGraph's job, not LCEL's.

## What we don't use from LangChain

- **Agents** (the old `AgentExecutor` API). LangGraph replaces this.
- **Memory** classes. Use LangGraph state + a checkpointer.
- **Callbacks**. Use LangSmith `@traceable` instead.
- **Document loaders** for production. They're a quick-prototype tool. For real ingestion, write the loader yourself.
- **Vector stores** as a black box. Pick one (Vertex Vector Search, pgvector, or other) and use the SDK directly.

## Streaming

Streaming flows through the model:

```python
async for chunk in model.astream(messages):
    yield chunk.content
```

For graph-level streaming, see `langgraph-patterns`.
