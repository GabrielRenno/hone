---
name: gcp-runtime
description: GCP runtime conventions — Cloud Run deploys, Secret Manager, Cloud Build CI, IAM basics. Auto-loads on Cloud Run, Secret Manager, gcloud, Cloud Build, or deployment work.
---

# GCP Runtime

Cloud Run is where agents serve traffic. Secret Manager is where credentials live. Cloud Build is CI.

## Cloud Run

Build for Cloud Run means: stateless container, listen on `$PORT`, fast cold starts, no local disk assumptions.

**Dockerfile** for a Cloud Run service:

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

# Cloud Run sets PORT, default 8080 for local docker run
ENV PORT=8080
CMD exec uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Use `exec` so signals propagate — Cloud Run sends SIGTERM for graceful shutdown, FastAPI handles it via uvicorn.

**Deploy** from a tagged commit:

```bash
gcloud run deploy <service-name> \
  --source . \
  --region us-central1 \
  --service-account <service>-sa@<project>.iam.gserviceaccount.com \
  --allow-unauthenticated=false \
  --min-instances 0 \
  --max-instances 10 \
  --concurrency 40 \
  --memory 1Gi \
  --cpu 1 \
  --timeout 300 \
  --set-secrets ANTHROPIC_API_KEY=anthropic-key:latest,LANGSMITH_API_KEY=langsmith-key:latest
```

Notes:
- `min-instances 0` for non-latency-critical agents (cold start is fine).
- `min-instances 1` if you need warm starts (costs more).
- `concurrency 40` is a good default for IO-bound agent code. Tune up for cheap models, down for expensive synthesis.
- `timeout 300` is the per-request cap. Long-running agents go through Pub/Sub instead — see `gcp-state-and-events`.

## Secret Manager

Secrets live in Secret Manager, not env files, not code. The pattern:

```python
# core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    anthropic_api_key: str
    langsmith_api_key: str
    gcp_project: str
    gcp_region: str = "us-central1"

    model_config = SettingsConfigDict(env_file=".env.dev", env_file_encoding="utf-8")
```

In dev, `.env.dev` is gitignored. In prod, Cloud Run injects the secrets as env vars via `--set-secrets`. Same code reads them from `os.environ` either way.

**Creating a secret:**

```bash
echo -n "sk-ant-..." | gcloud secrets create anthropic-key --data-file=-
gcloud secrets versions add anthropic-key --data-file=- < new-key.txt
```

**Granting Cloud Run access:**

```bash
gcloud secrets add-iam-policy-binding anthropic-key \
  --member="serviceAccount:<service>-sa@<project>.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

Always use a dedicated service account per service. Don't use the default Compute Engine SA.

## Cloud Build CI

`cloudbuild.yaml` for an automated deploy on push:

```yaml
steps:
  - name: 'python:3.12-slim'
    entrypoint: bash
    args:
      - -c
      - |
        pip install uv && uv sync --frozen
        uv run pytest -q
        uv run ruff check .
        uv run mypy --strict app/

  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-central1-docker.pkg.dev/$PROJECT_ID/services/<service>:$COMMIT_SHA', '.']

  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-central1-docker.pkg.dev/$PROJECT_ID/services/<service>:$COMMIT_SHA']

  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk:slim'
    entrypoint: gcloud
    args:
      - run
      - deploy
      - <service>
      - --image=us-central1-docker.pkg.dev/$PROJECT_ID/services/<service>:$COMMIT_SHA
      - --region=us-central1
      - --service-account=<service>-sa@$PROJECT_ID.iam.gserviceaccount.com

options:
  logging: CLOUD_LOGGING_ONLY
```

Trigger this from a GitHub push to `main` via Cloud Build's GitHub integration.

## IAM principles

- **One service account per Cloud Run service.** Named `<service>-sa@<project>.iam.gserviceaccount.com`.
- **Least privilege.** Grant only what the service actually needs (specific secrets, specific topics, specific Firestore collections).
- **No shared SAs.** Two services sharing an SA is a foot-gun.
- **No keys downloaded.** Use Workload Identity for cross-service auth, never JSON keys checked into anything.

## What to skip

- **Cloud Functions.** Cloud Run does everything Cloud Functions does, with more control. Pick one runtime, stick with it.
- **App Engine.** Legacy. Don't start new things here.
- **GKE for agents.** Overkill until you genuinely need scheduling primitives. Cloud Run handles 99% of agent traffic.
