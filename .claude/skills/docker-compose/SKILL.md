---
name: docker-compose
description: Local dev stack via Docker Compose — Cloud Run-compatible Dockerfile, Pub/Sub + Firestore emulators for offline dev. Auto-loads on Docker, Dockerfile, compose, or local-dev work.
---

# Docker Compose

The local stack mirrors Cloud Run as closely as possible. Pub/Sub and Firestore have official emulators — use them.

## Dockerfile (Cloud Run-compatible)

```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

FROM python:3.12-slim AS runtime
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONUNBUFFERED=1
COPY app ./app

ENV PORT=8080
CMD exec uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Same image in dev and prod. Only difference is what env vars are injected.

## docker-compose.yml

```yaml
services:
  api:
    build:
      context: .
      target: runtime
    command: uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
    volumes:
      - ./app:/app/app
    ports: ["8080:8080"]
    env_file: .env.dev
    environment:
      FIRESTORE_EMULATOR_HOST: firestore:8080
      PUBSUB_EMULATOR_HOST: pubsub:8085
    depends_on: [firestore, pubsub]

  firestore:
    image: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    command: >
      gcloud beta emulators firestore start
      --host-port=0.0.0.0:8080
      --project=local-dev
    ports: ["8081:8080"]

  pubsub:
    image: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    command: >
      gcloud beta emulators pubsub start
      --host-port=0.0.0.0:8085
      --project=local-dev
    ports: ["8085:8085"]

  pubsub-init:
    # Creates the dev topic + push subscription pointing at the api service
    image: gcr.io/google.com/cloudsdktool/cloud-sdk:slim
    depends_on: [pubsub, api]
    environment:
      PUBSUB_EMULATOR_HOST: pubsub:8085
    command: >
      bash -c "
      curl -X PUT http://pubsub:8085/v1/projects/local-dev/topics/agent-runs &&
      curl -X PUT http://pubsub:8085/v1/projects/local-dev/subscriptions/agent-runs-push
      -H 'Content-Type: application/json'
      -d '{\"topic\":\"projects/local-dev/topics/agent-runs\",
            \"pushConfig\":{\"pushEndpoint\":\"http://api:8080/internal/runs/execute\"}}'"
```

If your agent doesn't use Pub/Sub yet, drop the `pubsub` and `pubsub-init` services. Same for `firestore`.

## docker-compose.test.yml (overrides)

```yaml
services:
  api:
    command: pytest -q
    volumes:
      - ./app:/app/app
      - ./tests:/app/tests
    environment:
      FIRESTORE_EMULATOR_HOST: ""  # tests use MemorySaver, not the emulator
      PUBSUB_EMULATOR_HOST: ""
    depends_on: []
```

Run with: `docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm api`

## Local workflow

```bash
docker compose up                                      # full stack with emulators
docker compose up -d firestore pubsub                  # just the emulators, run app outside docker
docker compose run --rm api pytest -k <pattern>        # targeted tests
docker compose run --rm api ruff check .               # lint
docker compose run --rm api mypy --strict app/         # types
```

## Why emulators, not real GCP

- Offline development. No GCP billing for local work.
- Deterministic state. Wipe and restart between test sessions.
- Same SDK code reads `FIRESTORE_EMULATOR_HOST` automatically — no code changes between local and prod.

## What stays in real GCP for dev

- **Anthropic API.** No emulator. Use a low-budget test key, or stub it via fake_llm in code paths.
- **Vertex AI models.** Same — real or stubbed. Don't try to emulate the model layer.
- **LangSmith.** Use a separate `dev` project in your LangSmith workspace.

## Don't

- Don't bake secrets into the image.
- Don't run as root in runtime. Add a non-root user if shipping to a hardened environment.
- Don't use `latest` tags for base images — pin a digest or version tag.
- Don't run the whole stack to debug a unit test. Run pytest directly.
