# Task: Classify Agent (Reference Task)

A reference task. Builds a minimal LangGraph agent with TDD.

## Setup
- git checkout starting-fixture
- uv sync

## Prompt
Implement a LangGraph agent named `classifier` that classifies user messages into one of three intents: tool_call, answer, clarify.

Requirements:
- StateGraph with two nodes: `classify` and `format`.
- State is a Pydantic v2 model with fields: messages (list), intent (str | None), final_output (str | None).
- The `classify` node uses `claude-sonnet-4-6` via `model_router.anthropic_chat_model()` with `with_structured_output(Classification)` where Classification is a Pydantic model with `intent: str` and `confidence: float`.
- The `format` node turns the classification into a final_output string.
- A conditional edge after `classify` ends the run if `confidence < 0.5`.
- All nodes are `@traceable`.
- Compile with `MemorySaver` for the test build.

Follow TDD strictly: write the failing tests first, then implement.

## Acceptance
Commands that must exit 0:
- pytest tests/agents/test_classifier.py -q
- ruff check .
- mypy --strict app/

## Rubric overrides
- Must use Pydantic v2 model for state (not bare TypedDict).
- Every node must be `@traceable` (check via grep).
- Must NOT instantiate ChatAnthropic directly inside nodes — must call model_router.
- Conditional edge must be a pure function (no async, no IO).
- Tests must use `fake_llm` fixture, not real LLM calls.
