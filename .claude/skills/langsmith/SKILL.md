---
name: langsmith
description: LangSmith for tracing agent runs in production and running prod-side evals. Auto-loads when adding tracing to a node, configuring LangSmith, or building an evaluator dataset. Local evals/run.py stays the primary harness regression tool — LangSmith is for actual agent runs.
---

# LangSmith

LangSmith captures every LangGraph run as a tree of spans you can inspect, replay, and score. In Hone, LangSmith is for production agent runs. The local `evals/run.py` stays the primary tool for harness regression.

## Setup

Three env vars enable tracing:

```
LANGSMITH_API_KEY=ls__...
LANGSMITH_PROJECT=aimana-<service-name>
LANGSMITH_TRACING=true
```

Pulled from Secret Manager at boot via `core/config.py`. The LangChain SDK reads them automatically. No init code needed.

## Tracing in nodes

```python
from langsmith import traceable

@traceable(name="classify_intent")
async def classify_intent(state: AgentState) -> dict:
    ...
```

Rules:
- Every LangGraph node is `@traceable`.
- Custom name when the function name is generic (`step_1`, `process`).
- Put it on the outermost function. LangChain primitives (`ChatModel`, `Tool`) trace themselves — don't double-wrap.

For non-graph functions (helpers, tool implementations) that you want visible in traces, also use `@traceable`.

## Run metadata

Attach metadata at invocation so you can filter traces later:

```python
config = {
    "configurable": {"thread_id": run_id},
    "metadata": {
        "user_id": user_id,
        "client": "acme-corp",
        "version": app_version,
    },
    "tags": ["prod", "v2"],
}
result = await graph.ainvoke(input_state, config=config)
```

Filter in LangSmith by metadata or tag to find slow runs, error patterns, specific clients.

## Evals — production side

LangSmith evals run on real production traces. Two patterns we use:

**1. LLM-as-judge on sampled runs.**

```python
from langsmith.evaluation import evaluate

def correctness_evaluator(run, example):
    # Compare run.outputs["final_answer"] against example.outputs["expected"]
    judge = anthropic_chat_model("claude-sonnet-4-6")
    verdict = judge.invoke(JUDGE_PROMPT.format(
        actual=run.outputs["final_answer"],
        expected=example.outputs["expected"],
    ))
    return {"key": "correctness", "score": parse_score(verdict)}

evaluate(
    target_function,
    data=dataset_name,
    evaluators=[correctness_evaluator],
)
```

**2. Heuristic checks on every run.**

Annotate runs in code:

```python
from langsmith import Client
client = Client()

if not result.get("final_answer"):
    client.create_feedback(run_id, key="empty_answer", score=0)
```

Feedback shows up in the LangSmith dashboard alongside traces. Useful for catching production regressions without writing a full eval suite.

## Datasets

Build datasets from production traces. In LangSmith UI: filter for traces you want, "Add to dataset." Or programmatically:

```python
from langsmith import Client
client = Client()

dataset = client.create_dataset("classify-intent-golden", description="...")
client.create_examples(
    inputs=[{"message": "..."}, ...],
    outputs=[{"intent": "tool_call"}, ...],
    dataset_id=dataset.id,
)
```

Run the dataset against any prompt or model variant and compare scores.

## What goes in LangSmith vs the local evals

| Question | Tool |
|---|---|
| "Did my hook change break the harness?" | local `evals/run.py` |
| "Did my prompt change improve answer quality?" | LangSmith |
| "Are production runs getting slower?" | LangSmith dashboards |
| "Does the new test-writer subagent produce better tests?" | local `evals/run.py` |
| "Which user prompts cause the most retries?" | LangSmith filters |

Local evals test the harness. LangSmith tests the agent.

## Cost note

Tracing every run can get expensive on high-volume agents. For high-traffic services, sample:

```python
import random

config = {
    "metadata": {...},
    "tags": ["prod"],
}
if random.random() < 0.1:  # 10% sample
    config["tags"].append("traced")
```

Then filter LangSmith dashboards by the `traced` tag. For low-volume agents, just trace everything.
