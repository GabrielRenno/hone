---
name: gcp-state-and-events
description: Firestore for agent state, Pub/Sub for async agent triggers. Auto-loads when working with agent state persistence, checkpointers, async dispatch, or Pub/Sub publishers/subscribers.
---

# GCP State and Events

Two services do most of the work outside Cloud Run: Firestore for state, Pub/Sub for events.

## Firestore as the LangGraph checkpointer

Workers are stateless. Agent state lives in Firestore so any worker can pick up any run. Implement a custom checkpointer or use the `langgraph-checkpoint-firestore` package if available.

Pattern:

```python
# tools/firestore_state.py
from google.cloud import firestore_v1
from langgraph.checkpoint.base import BaseCheckpointSaver, Checkpoint, CheckpointTuple

class FirestoreCheckpointer(BaseCheckpointSaver):
    def __init__(self, client: firestore_v1.AsyncClient, collection: str = "agent_checkpoints"):
        self._client = client
        self._collection = collection

    async def aput(self, config, checkpoint, metadata):
        thread_id = config["configurable"]["thread_id"]
        doc_ref = self._client.collection(self._collection).document(thread_id)
        await doc_ref.set({
            "checkpoint": serialize(checkpoint),
            "metadata": metadata,
            "updated_at": firestore_v1.SERVER_TIMESTAMP,
        })

    async def aget_tuple(self, config) -> CheckpointTuple | None:
        thread_id = config["configurable"]["thread_id"]
        doc = await self._client.collection(self._collection).document(thread_id).get()
        if not doc.exists:
            return None
        data = doc.to_dict()
        return CheckpointTuple(
            config=config,
            checkpoint=deserialize(data["checkpoint"]),
            metadata=data["metadata"],
        )

    # ... aput_writes, alist as needed
```

Wire it in graph compilation:

```python
def build_graph():
    g = StateGraph(AgentState)
    # ... add nodes, edges ...
    return g.compile(checkpointer=FirestoreCheckpointer(get_firestore_client()))
```

## Firestore conventions

- One collection per agent type: `classifier_runs`, `support_agent_runs`. Don't mix.
- Document ID is the LangGraph `thread_id` (which equals the run_id).
- Use Firestore async client (`google.cloud.firestore_v1.AsyncClient`) — sync blocks the worker.
- Index any field you'll query frequently (status, user_id, created_at). Add indexes in `firestore.indexes.json`.
- Set TTL on completed-run documents (Firestore TTL field). Default to 90 days.

## Querying for stuck runs

```python
async def find_stuck_runs(max_age_hours: int = 1) -> list[dict]:
    cutoff = datetime.now(UTC) - timedelta(hours=max_age_hours)
    snapshots = self._client.collection("agent_checkpoints") \
        .where("metadata.status", "==", "running") \
        .where("updated_at", "<", cutoff) \
        .stream()
    return [snap.to_dict() async for snap in snapshots]
```

A scheduled Cloud Run job (or Cloud Scheduler + Pub/Sub) checks this hourly and re-queues stuck runs.

## Pub/Sub for async agent triggers

Long-running agents don't run inside the HTTP request. Pattern:

```
Client → POST /runs (synchronous, returns 202)
              ↓
   1. Write run metadata to Firestore (status=queued)
   2. Publish to topic agent-runs:<env>
              ↓
        Pub/Sub push → POST /internal/runs/execute
              ↓
        Build graph, run to completion, update Firestore
```

**Publisher:**

```python
# tools/pubsub.py
from google.cloud import pubsub_v1

class RunPublisher:
    def __init__(self, project: str, topic: str):
        self._client = pubsub_v1.PublisherClient()
        self._topic_path = self._client.topic_path(project, topic)

    async def publish(self, run_id: str, payload: dict) -> None:
        message = json.dumps({"run_id": run_id, **payload}).encode("utf-8")
        future = self._client.publish(self._topic_path, message, run_id=run_id)
        # Don't await unless you need confirmation. Cloud Run will retry on failure.
```

**Subscriber endpoint** (Pub/Sub push):

```python
@router.post("/internal/runs/execute", status_code=204)
async def execute_run(envelope: PubSubEnvelope) -> None:
    payload = envelope.decode()  # base64 → dict
    run_id = payload["run_id"]

    config = {"configurable": {"thread_id": run_id}}
    try:
        await graph.ainvoke(payload["input"], config=config)
    except Exception as e:
        # Pub/Sub will retry. After max retries, message goes to dead letter.
        raise HTTPException(status_code=500, detail=str(e))
```

Pub/Sub retries automatically on non-2xx. Configure a dead letter topic for messages that exhaust retries.

## Idempotency

Pub/Sub guarantees at-least-once delivery. Your handler must be idempotent.

Pattern: check Firestore for the run_id before starting. If it's already `completed`, return 204 without re-running:

```python
existing = await firestore_client.collection("agent_checkpoints").document(run_id).get()
if existing.exists and existing.to_dict()["metadata"]["status"] == "completed":
    return  # already done, ack the message
```

For mid-run idempotency, the LangGraph checkpointer handles it — re-invoking with the same `thread_id` resumes from the last checkpoint.

## Push vs pull

Use Pub/Sub **push** (POST to a Cloud Run URL) for agent runs. Reasons:
- Cloud Run scales to zero when idle, push wakes it up.
- No worker pool to manage.
- Auth via OIDC token, simpler than IAM-based pull.

Use **pull** only for high-throughput batch processing where you need explicit flow control.

## Local development

For local dev, use the Pub/Sub emulator:

```bash
gcloud beta emulators pubsub start --project=local-dev
export PUBSUB_EMULATOR_HOST=localhost:8085
```

Firestore also has an emulator:

```bash
gcloud beta emulators firestore start --host-port=localhost:8080
export FIRESTORE_EMULATOR_HOST=localhost:8080
```

Both are wired into `docker-compose.yml` (see `docker-compose` skill).

## Anti-patterns

- **Sync Firestore client in async code.** Blocks the worker. Always use the async client.
- **Pub/Sub message > 10MB.** Will fail. For big payloads, write to GCS, send the GCS path in the message.
- **Holding state in module globals.** Workers are ephemeral. Read from Firestore on every invocation.
- **Skipping idempotency.** You'll get duplicate runs eventually. Plan for it.
