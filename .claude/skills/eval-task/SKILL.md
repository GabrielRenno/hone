---
name: eval-task
description: Describes how local golden tasks work. Manual-only — invoked by /score and the eval runner. Local evals test the harness; LangSmith handles agent runs in production (see langsmith skill).
disable-model-invocation: true
---

# Eval Task

Two eval systems in Hone:
- **Local** (this skill, `evals/run.py`) — tests the harness itself. Did your hook change break the agent? Did the new test-writer subagent regress?
- **LangSmith** (separate skill) — tests the agent. Did your prompt change improve answer quality on real traces?

This skill covers the local one.

## Task file structure

Golden tasks live in `evals/tasks/<task>.md`:

```markdown
# <Task name>

## Setup
Commands to run before invoking Claude. Sets up fixture state.
- git checkout <starting-commit>
- uv sync

## Prompt
The exact prompt to send to Claude in headless mode:
> Implement a LangGraph agent with one classify node and one respond node.
> The classify node uses claude-sonnet-4-6 with structured output.
> Tests must be written first.

## Acceptance
Commands that must exit 0:
- pytest tests/test_agent.py -q
- ruff check .
- mypy --strict app/

## Rubric overrides
Optional. Specific behavioral checks:
- Must use @traceable on every node
- Must use Pydantic for the state schema (not bare TypedDict)
- Must NOT instantiate models inside nodes — use model_router
```

## Default rubric

Lives in `evals/rubric.md`. Applies to every task. Tasks add their own checks under `## Rubric overrides`.

## Manual invocation

If invoked directly (`/eval-task <name>`):
1. Read `evals/tasks/<name>.md`.
2. Show the user the setup commands and the prompt.
3. Ask for confirmation before running setup (some tasks reset git state).
4. After confirmation, run setup and tell the user to invoke Claude with the prompt.
5. Don't fork Claude processes — the runner script does that.

## When to add a task

Add a golden task when:
- You add a new harness primitive (skill, hook, subagent) and want to test it doesn't break.
- A real bug slipped through — capture it as a task so future runs catch the regression.
- You change a hook and want to confirm agents still work.

## When to use LangSmith instead

For anything testing the actual agent behavior on real traffic — prompt iteration, model swaps, eval-driven prompt engineering — use LangSmith. See the `langsmith` skill.
