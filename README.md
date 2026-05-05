# Hone

A Claude Code harness for AIMANA's stack: LangGraph agents on GCP, served via FastAPI, deployed to Cloud Run, traced through LangSmith.

Hone enforces the discipline that makes Claude Code reliable for shipping production agents — tight TDD, blocked secret/protected paths, automatic formatting and type-checking, structured plan-build-check-score loop.

This isn't a finished product. It's a working starting point. Drop it into a project, adjust a handful of paths, and the harness is live.

---

## What's in here

```
.
├── CLAUDE.md                     # Lean root memory file (~50 lines)
├── docs/
│   ├── conventions.md            # Imported by CLAUDE.md
│   ├── architecture.md           # Three-layer architecture: API → graph → tools
│   └── plans/                    # Plan files for in-flight features
├── .claude/
│   ├── settings.json             # Hooks + permission denylist
│   ├── agents/                   # explorer, critic, test-writer
│   ├── skills/                   # 11 skills, auto-loaded by description
│   ├── commands/                 # /plan /build /check /score /clear-and-go
│   ├── hooks/                    # 6 shell scripts
│   └── logs/                     # gitignored, written by hooks
├── evals/
│   ├── rubric.md                 # Behavioral checklist
│   ├── tasks/                    # Local golden tasks (test the harness)
│   ├── runs/                     # Eval reports
│   └── run.py                    # Headless eval runner
└── .github/workflows/
    └── eval.yml                  # Runs evals on PRs
```

---

## The stack Hone targets

- **Python 3.12**, LangGraph, LangChain, LangSmith
- **FastAPI** as the thin API layer wrapping agents
- **Pydantic v2** for state schemas and external IO
- **GCP**: Cloud Run, Secret Manager, Vertex AI, Pub/Sub, Firestore, Cloud Build
- **pytest + httpx.AsyncClient** for tests
- **Ruff + mypy --strict**

If you're working in a different stack, fork and adjust the skills. The harness primitives (CLAUDE.md, hooks, subagents, commands, evals) are stack-agnostic.

---

## The 11 skills

Workflow:
- `prd-interview` — turns ideas into PRDs via structured questions
- `vertical-slice` — cuts PRDs into independently shippable units

API + tests:
- `fastapi-patterns` — thin API layer wrapping graphs
- `pytest-tdd` — async testing with MemorySaver, fake LLMs, deterministic harness

Agent layer:
- `langgraph-patterns` — state, nodes, edges, checkpointers, subgraphs
- `langchain-utilities` — chat models, output parsers, model routing, tool decorators
- `langsmith` — production tracing and evals

Infrastructure:
- `gcp-runtime` — Cloud Run, Secret Manager, Cloud Build CI
- `gcp-state-and-events` — Firestore checkpointer, Pub/Sub publishers/subscribers
- `docker-compose` — local dev with Pub/Sub + Firestore emulators

Manual:
- `eval-task` — describes the local eval format (manual-only)

---

## Setup

### 1. Drop Hone into your repo

```bash
cp -r .claude your-project/
cp -r docs your-project/
cp -r evals your-project/
cp CLAUDE.md your-project/
cp -r .github your-project/  # if you don't already have one
```

### 2. Make hooks executable

```bash
chmod +x .claude/hooks/*.sh
```

### 3. Edit `CLAUDE.md`

Replace `<project-name>` with the actual project name. Trim the Stack section if you're not using all of it. Keep it under ~80 lines.

### 4. Verify the toolchain

The hooks expect these tools on the PATH:
- `python3`, `git`
- `ruff`, `mypy`, `pytest`
- `gcloud`, `gh` (optional but recommended)

If you use `uv`, install them as dev deps and ensure `.venv/bin` is on the PATH when Claude Code runs.

### 5. Set up `.gitignore`

The shipped `.gitignore` covers Hone's own outputs. Merge with your project's gitignore as needed.

### 6. Run a smoke test

In your project, open Claude Code:
```
/plan add a /healthz endpoint that returns the current server time
```

You should see the PRD interview kick off, ask 5–8 questions, and write `docs/plans/healthz.md`. Then:

```
/build healthz
```

The `test-writer` subagent should write failing tests, the main agent should implement, hooks should format and typecheck, and the Stop hook should hold the line if anything's red.

---

## Customizing

### Add a project-specific skill

```bash
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'END'
---
name: my-skill
description: Auto-loads when ... (be specific or it'll load too often)
---

# My Skill

Body here.
END
```

The description is the auto-load trigger. Keep it narrow.

### Add a hook

Edit `.claude/settings.json`. Hook events: `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `UserPromptSubmit`. Reference: https://code.claude.com/docs/en/hooks

### Add a golden task

```bash
cp evals/tasks/example-create-user.md evals/tasks/your-task.md
# Edit Setup, Prompt, Acceptance, Rubric overrides.
python evals/run.py --task your-task
```

---

## Running evals

```bash
python evals/run.py                              # all tasks
python evals/run.py --task <name>                # one task
ls -t evals/runs/ | head -1                      # latest report
```

Needs the `claude` CLI:
```
npm install -g @anthropic-ai/claude-code
```

The CI workflow at `.github/workflows/eval.yml` runs the same suite on PRs that touch `CLAUDE.md`, `.claude/`, or `evals/`.

---

## Rollout order

You don't install everything on day one. Order matters.

**Day 1.** Drop in CLAUDE.md and the four most important hooks (block-secrets, block-protected, format-on-write, tests-must-pass). Use the harness on real work for a few days. See what hurts.

**Day 2.** Add the three subagents and the slash commands. Use them on real work for a week.

**Day 3.** Add the skills relevant to your stack. Don't blanket-install — import only the ones that match work you actually do.

**Day 4.** Build the eval harness. Write 3–5 golden tasks based on real work. Set up the GitHub Action.

**Beyond.** Iterate based on what evals tell you.

---

## What's deliberately not here

- **Plugin manifest.** Hone is a personal harness. To package for sharing, wrap `.claude/` in a `plugin.json` per the [plugin docs](https://code.claude.com/docs/en/plugins).
- **Multi-agent parallelism.** Three sequential subagents handle the workflow. Parallel agent teams aren't worth the complexity for solo work.
- **OTel tracing.** LangSmith covers the agent layer. Hook logs cover the harness layer. OTel is for when you have multiple services and dashboards.
- **Memory beyond CLAUDE.md.** Claude Code's auto-memory feature handles implicit pattern learning. Don't build a custom memory system.

---

## References

- [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Claude Code subagents](https://code.claude.com/docs/en/sub-agents)
- [LangGraph docs](https://langchain-ai.github.io/langgraph/)
- [LangSmith docs](https://docs.smith.langchain.com/)

---

Built at AIMANA. Maintained as needed, not as theater.
