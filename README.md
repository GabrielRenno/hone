# Hone

A Claude Code harness that enforces discipline for shipping production agents. Built for LangGraph + FastAPI + GCP, but the core primitives (hooks, subagents, commands, context management) work with any stack.

Hone solves the gap between "Claude Code can write code" and "Claude Code reliably ships production software" — tight TDD, blocked secrets, automatic formatting, proactive context management, and a structured plan-build-check-score workflow.

## Quick Install

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/GabrielRenno/hone/main/install.sh | bash
```

That's it. The installer copies the harness files into your project, makes hooks executable, merges `.gitignore` entries, and tells you what to do next. It won't overwrite existing files.

---

## Table of Contents

- [Installation](#installation)
- [How It Works](#how-it-works)
- [The Workflow](#the-workflow)
- [Context Management](#context-management)
- [Hooks](#hooks)
- [Subagents](#subagents)
- [Commands](#commands)
- [Skills](#skills)
- [Eval Harness](#eval-harness)
- [Customizing](#customizing)
- [Rollout Order](#rollout-order)
- [File Reference](#file-reference)

---

## Installation

### One command (recommended)

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/GabrielRenno/hone/main/install.sh | bash
```

The installer:
- Clones Hone into a temp directory
- Copies `.claude/`, `docs/`, `evals/`, `CLAUDE.md`, and `.github/workflows/eval.yml`
- Skips files that already exist (won't overwrite your work)
- Makes hooks executable
- Merges `.gitignore` entries
- Cleans up the temp directory

### Manual install

If you prefer to do it yourself:

```bash
git clone https://github.com/GabrielRenno/hone.git /tmp/hone
cp -r /tmp/hone/.claude .
cp -r /tmp/hone/docs .
cp -r /tmp/hone/evals .
cp /tmp/hone/CLAUDE.md .
mkdir -p .github/workflows && cp /tmp/hone/.github/workflows/eval.yml .github/workflows/
chmod +x .claude/hooks/*.sh
rm -rf /tmp/hone
```

### After installing

```bash
# 1. Edit CLAUDE.md — replace <project-name>, trim the stack section to match yours
vi CLAUDE.md

# 2. Verify toolchain
python3 --version && ruff --version && mypy --version && pytest --version

# 3. Run a smoke test — open Claude Code and type:
#    /plan add a /healthz endpoint that returns the current server time
claude
```

The PRD interview should kick off, ask questions, and write `docs/plans/healthz.md`. Then run `/build healthz` — the test-writer subagent writes failing tests, the main agent implements, hooks format and typecheck, and the Stop hook blocks if anything's red.

### Prerequisites

- [Claude Code](https://claude.ai/download) installed (`npm install -g @anthropic-ai/claude-code`)
- `git`, `python3` on your PATH
- `ruff`, `mypy`, `pytest` (install as dev deps or globally)
- `gcloud`, `gh` (optional, for GCP deploys and GitHub ops)

---

## How It Works

Hone is not an application — it's a configuration layer. It consists of five primitives that shape how Claude Code behaves in your project:

### 1. CLAUDE.md — The root instructions

A lean file (~60 lines) that tells Claude Code your stack, architecture, non-negotiables (TDD, `@traceable`, Pydantic, etc.), and workflow. Claude reads this at the start of every session.

It also contains **Compact Instructions** — rules that tell the auto-compactor what to preserve (decisions, file paths, test state) and what to discard (raw file contents, verbose tool output). This is critical for long sessions.

### 2. Hooks — Automated guardrails

Six shell scripts in `.claude/hooks/` that run automatically at lifecycle points:

| Hook | When it runs | What it does |
|------|-------------|-------------|
| `block-secrets.sh` | Before any Read/Edit/Write | Blocks access to `.env`, `.pem`, `.key`, credential files |
| `block-protected.sh` | Before any Edit/Write | Blocks edits to `migrations/`, `.git/`, `node_modules/`, `.venv/` |
| `format-on-write.sh` | After any Edit/Write (async) | Runs `ruff format` + `ruff check --fix` on edited Python files |
| `typecheck-on-write.sh` | After any Edit/Write | Runs `mypy --strict` on edited files, surfaces errors |
| `tests-must-pass.sh` | When Claude tries to stop | Blocks Claude from ending its turn if tests are failing |
| `inject-context.sh` | On every user prompt | Injects git branch, recent commits, active plan, checkpoint state |

Hooks are configured in `.claude/settings.json` alongside a permission denylist that blocks `rm -rf`, `git push --force`, and `git reset --hard`.

### 3. Subagents — Specialized workers

Three subagents in `.claude/agents/` with constrained tool access:

| Subagent | Tools | Purpose |
|----------|-------|---------|
| `explorer` | Read, Grep, Glob | Read-only repo navigation. Returns precise file paths and line numbers, never raw content dumps. |
| `critic` | Read, Grep, Bash | Code review. Surfaces correctness, scope creep, security, and architecture issues. Ignores style (Ruff handles that). |
| `test-writer` | Read, Grep, Edit, Write | Writes failing pytest tests. Never writes implementation code. |

Subagents run in isolated context — their verbose work doesn't pollute the main conversation.

### 4. Commands — Workflow steps

Five slash commands in `.claude/commands/`:

| Command | What it does |
|---------|-------------|
| `/plan <idea>` | Runs a PRD interview (asks structured questions), writes to `docs/plans/<slug>.md` |
| `/build <slice>` | TDD loop: test-writer writes failing tests, main agent implements, hooks enforce quality |
| `/check` | Delegates to the critic subagent for code review of the current diff |
| `/score` | Scores the current diff against `evals/rubric.md` (10-item behavioral checklist) |
| `/clear-and-go <slug>` | Resets context window, rehydrates plan state, shows progress summary |

### 5. Skills — Stack-specific knowledge

Twelve auto-loaded skills in `.claude/skills/` that teach Claude your stack's patterns:

**Workflow:**
- `prd-interview` — structured questions to turn ideas into PRDs
- `vertical-slice` — cuts PRDs into independently shippable units

**API + Tests:**
- `fastapi-patterns` — thin API layer wrapping LangGraph graphs
- `pytest-tdd` — async testing with `MemorySaver`, `fake_llm` fixture, deterministic harness

**Agent layer:**
- `langgraph-patterns` — state schemas, nodes, edges, checkpointers, subgraphs
- `langchain-utilities` — chat models, output parsers, model routing, tool decorators
- `langsmith` — production tracing and evals

**Infrastructure:**
- `gcp-runtime` — Cloud Run, Secret Manager, Cloud Build CI
- `gcp-state-and-events` — Firestore checkpointer, Pub/Sub publishers/subscribers
- `docker-compose` — local dev with Pub/Sub + Firestore emulators

**Context:**
- `context-management` — proactive context hygiene (always loaded, see below)

**Manual:**
- `eval-task` — describes the local eval format

---

## The Workflow

Hone enforces a structured development loop:

```
/plan <idea>
    │
    ▼
  PRD interview (structured questions)
  Writes docs/plans/<slug>.md
    │
    ▼
  Vertical slicing (3-7 shippable slices)
  Appended to plan file
    │
    ▼
/build <slice>
    │
    ▼
  test-writer writes failing tests
  Main agent implements minimum code
  Hooks auto-format + typecheck
  Stop hook blocks if tests are red
    │
    ▼
/check
    │
    ▼
  Critic reviews diff
  (correctness, scope, security, architecture)
    │
    ▼
/score
    │
    ▼
  Rubric scoring (10 items, 8/10 = green)
    │
    ▼
  Commit → /clear-and-go → next slice
```

Each slice is independently shippable and reversible. One slice per branch. Rebase before merging.

---

## Context Management

Long Claude Code sessions (2+ hours) degrade past ~100k tokens — the model starts hallucinating, forgetting decisions, and re-exploring files it already read. Hone manages this proactively through five mechanisms:

### Auto-compact at 50%

The `inject-context.sh` hook exports `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`, triggering auto-compact at ~100k tokens instead of the default ~190k. This fires early enough to prevent quality degradation.

### Compact Instructions

The `## Compact Instructions` section in CLAUDE.md tells the compactor what to preserve:
- Current slice and acceptance criteria
- All decisions made and their reasoning
- File paths modified
- Test state
- User preferences and corrections

And what to discard:
- Raw file contents (files still exist on disk)
- Verbose tool output (test logs, git diffs, grep results)
- Intermediate reasoning

### Checkpoint files

At natural phase transitions (after exploration, after tests pass, after completing a slice), Claude writes a state snapshot to `.claude/checkpoints/current.md`:

```markdown
# Checkpoint — 2026-05-05T14:32Z

## Active slice
classify-001: Implement classifier agent

## Decisions made
- Using Pydantic v2 state for structured validation
- model_router routes classify to gemini-2.5-flash

## Files modified
- app/agents/classifier/state.py (created)
- app/agents/classifier/nodes.py (created)

## Test state
- 3 tests written, 2 passing, 1 failing

## What's next
- Fix the failing test — edge function not wired up
```

This file is injected into every prompt by `inject-context.sh`. After a compact, Claude immediately has the full state snapshot. Checkpoint files are gitignored — they're session scratchpads, not committed artifacts.

### Subagent-first exploration

The `context-management` skill teaches Claude to route noisy work through subagents:
- Use `explorer` to map out code, then act on the file paths it returns
- Use subagents for test output analysis, multi-file searches, log review
- Never read 5+ files into main context to "understand the codebase"

### Targeted reads

Instead of reading entire files, Claude is taught to:
1. `Grep` for the function/class name to get the line number
2. `Read` with `offset` and `limit` to get just the 20-50 lines needed
3. Act on what was read

Files under ~100 lines can be read in full — the cost is negligible.

---

## Hooks

### block-secrets.sh (PreToolUse — Read, Edit, Write)

Blocks access to files matching secret patterns: `.env`, `.pem`, `.key`, `credentials.*`, `secrets.*`, `*_secret.*`, `.p12`, `id_rsa.*`. Exits with code 2 to block the tool.

### block-protected.sh (PreToolUse — Edit, Write)

Blocks edits to protected paths: `migrations/`, `.git/`, `node_modules/`, `.venv/`, `dist/`, `build/`. Directs to proper tools (e.g., alembic for migrations).

### format-on-write.sh (PostToolUse — async)

Runs `ruff format` and `ruff check --fix` on edited Python files. Runs asynchronously so it doesn't block Claude's turn.

### typecheck-on-write.sh (PostToolUse)

Runs `mypy --strict` on edited Python files (skips `tests/`). Non-blocking — surfaces errors for Claude to fix but doesn't halt progress.

### tests-must-pass.sh (Stop)

When Claude tries to end its turn, this hook:
1. Derives a pytest `-k` pattern from changed files via git
2. Runs `pytest -k <pattern> --maxfail=3`
3. Blocks the turn (exit 2) if tests are failing
4. Allows the turn to end if tests pass or nothing changed

### inject-context.sh (UserPromptSubmit)

Runs on every user prompt. Does three things:
1. Exports `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` for early auto-compaction
2. Injects git context (branch, recent commits, active plan file)
3. Injects checkpoint state from `.claude/checkpoints/current.md` if it exists

### Permission denylist

Configured in `.claude/settings.json`:
- `rm -rf` (all variants)
- `git push --force` and `git push -f`
- `git reset --hard`

---

## Subagents

### explorer

Read-only repo navigator. Use when the question is "where is X" or "find all Y in this codebase."

- Tools: Read, Grep, Glob
- Returns file paths and line numbers, not raw content
- Leads with a one-sentence answer, then references
- Never proposes changes or reads files unrelated to the question

### critic

Code reviewer. Invoked by `/check` or when asking for a diff review.

- Tools: Read, Grep, Bash
- Reads `git diff main...HEAD` and affected files in full
- Surfaces issues in four categories: **Correctness** > **Scope creep** > **Security** > **Architecture violations**
- Does NOT flag formatting (Ruff), types (mypy), or style preferences
- If nothing is wrong, says so in one line

### test-writer

Pytest test writer. Invoked by `/build` or when asked to add tests.

- Tools: Read, Grep, Edit, Write
- Produces a test file that fails initially and would pass after correct implementation
- Uses `httpx.AsyncClient` for endpoints, `MemorySaver` for graphs, `fake_llm` for LLM stubs
- Every test asserts on specific behavior, not just status codes
- Never writes implementation code

---

## Commands

### /plan \<idea\>

Runs the `prd-interview` skill. Asks 15-30 structured questions (one at a time) covering: who triggers this, input/output shapes, edge cases, error handling, success criteria, scope. Writes the PRD to `docs/plans/<slug>.md`. Does not propose vertical slices or write code.

### /build \<slice\>

Implements a vertical slice using strict TDD:
1. Reads `docs/plans/<slug>.md`, identifies the target slice
2. Delegates to `test-writer` for failing tests
3. Runs tests to confirm failure
4. Implements minimum code to pass
5. Hooks auto-format and typecheck
6. Stop hook blocks if tests are red
7. Summarizes when green

### /check

Delegates to the `critic` subagent. Passes through findings grouped by category (correctness, scope, security, architecture) or reports "nothing wrong."

### /score

Reads `evals/rubric.md` and scores the current diff against 10 items:
- Process discipline: tests before implementation, stayed in scope, no hook bypass
- Output quality: no over-engineering, architecture respected, Pydantic at boundaries
- Verification gates: pytest passes, ruff passes, mypy passes, coverage rule

Each item is pass/fail/partial. 8/10 or better is a green run. Report is saved to `evals/runs/manual-<timestamp>.md`.

### /clear-and-go \<slug\>

Resets context between slices:
1. Reads `docs/plans/<slug>.md` and current state of referenced files
2. Shows a one-paragraph summary: which slices are done, which is next, test status
3. Waits for instruction — does not start coding

---

## Skills

Skills auto-load based on their description matching the current task context. They teach Claude stack-specific patterns without cluttering CLAUDE.md.

### Workflow skills

**prd-interview** — Turns ideas into PRDs through structured questions. Covers triggers, input/output shapes, edge cases, error handling, success criteria, and scope. Writes to `docs/plans/<slug>.md`.

**vertical-slice** — Cuts PRDs into 3-7 independently shippable units. Each slice touches every needed layer, has working tests, can ship to main without breaking anything, and is reversible.

### API + Test skills

**fastapi-patterns** — Thin API layer patterns. Routes validate input, invoke the compiled graph, return the response. Covers synchronous, async (Pub/Sub + 202), and streaming (SSE) patterns. No business logic in routes.

**pytest-tdd** — Testing patterns for LangGraph agents and FastAPI endpoints. `conftest.py` layout with `client`, `graph`, and `fake_llm` fixtures. Tests nodes (unit), graphs (integration), edges (pure functions), API layer, and async runs.

### Agent skills

**langgraph-patterns** — State schemas (TypedDict or Pydantic v2 with `Annotated[..., add_messages]`), async `@traceable` nodes, pure edge functions, graph building, checkpointers, tool calling, subgraphs.

**langchain-utilities** — Chat models wrapped in functions for easy swapping, centralized model routing (`model_for_task()`), structured output via `with_structured_output()`, `ChatPromptTemplate`, `@tool` decorator.

**langsmith** — Production tracing with `@traceable` on every node, run metadata for filtering, LLM-as-judge evals on sampled runs, dataset building from production traces.

### Infrastructure skills

**gcp-runtime** — Cloud Run (two-stage Dockerfile, `exec uvicorn`), Secret Manager (Pydantic Settings), Cloud Build CI (pytest/ruff/mypy + deploy), IAM (one SA per service, least privilege).

**gcp-state-and-events** — Firestore as LangGraph checkpointer (custom `BaseCheckpointSaver`), Pub/Sub for async agent triggers (publish/push pattern), idempotency via status checks, emulators for local dev.

**docker-compose** — Local dev stack with Firestore and Pub/Sub emulators. Same Docker image for dev and prod (only env vars differ). Test override skips emulators (tests use `MemorySaver`).

### Context skill

**context-management** — Always loaded. Teaches five behaviors: route noisy work through subagents, read targeted sections not full files, write checkpoints at phase transitions, prefer targeted tool calls, summarize before continuing. See [Context Management](#context-management).

---

## Eval Harness

### Rubric (evals/rubric.md)

10-item behavioral checklist applied to every golden task:

1. Tests written before implementation (verifiable from git log)
2. Stayed within slice scope
3. No hook bypass
4. No over-engineering
5. Architecture respected (routes invoke graphs, not nodes directly)
6. Pydantic models at boundaries
7. `pytest` passes
8. `ruff check .` passes
9. `mypy --strict app/` passes
10. Coverage rule (each test asserts specific behavior)

### Eval runner (evals/run.py)

Runs Claude Code in headless mode against golden tasks:

```bash
python evals/run.py                       # all tasks
python evals/run.py --task <name>         # one task
python evals/run.py --only-failing        # re-run failed from last report
```

Process:
1. Runs setup commands from the task file
2. Invokes `claude -p <prompt> --dangerously-skip-permissions`
3. Captures git diff stats
4. Runs acceptance commands (pytest, ruff, mypy)
5. Scores rubric (auto-checks what it can, marks rest as "manual")
6. Writes JSON report to `evals/runs/`

### Golden tasks (evals/tasks/)

Each task is a markdown file with four sections:

```markdown
## Setup
Commands to run before Claude (e.g., git checkout, uv sync)

## Prompt
Exact prompt to send Claude in headless mode

## Acceptance
Commands that must exit 0 (e.g., pytest, ruff, mypy)

## Rubric overrides
Additional behavioral checks beyond the default rubric
```

Two example tasks are included:
- `example-classify-agent.md` — Build a minimal LangGraph agent with TDD
- `example-create-user.md` — Build an async endpoint with Pub/Sub

### CI (`.github/workflows/eval.yml`)

Runs the eval suite on PRs that touch `CLAUDE.md`, `.claude/`, `evals/`, or `docs/conventions.md`. Uploads the report as a build artifact.

---

## Customizing

### Add a skill

```bash
mkdir -p .claude/skills/my-skill
```

Create `.claude/skills/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Auto-loads when ... (be specific or it loads too often)
---

# My Skill

Patterns and rules here.
```

The description field is the auto-load trigger. Keep it narrow — a skill that loads on every task wastes context.

### Add a hook

Edit `.claude/settings.json`. Available events: `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `UserPromptSubmit`. Each hook receives JSON on stdin describing the tool call.

### Add a golden task

```bash
cp evals/tasks/example-create-user.md evals/tasks/your-task.md
# Edit the Setup, Prompt, Acceptance, and Rubric overrides sections
python evals/run.py --task your-task
```

### Adjust the stack

If you're not using the full AIMANA stack, remove irrelevant skills:

```bash
# Not using GCP? Remove these:
rm -rf .claude/skills/gcp-runtime
rm -rf .claude/skills/gcp-state-and-events
rm -rf .claude/skills/docker-compose

# Not using LangGraph? Remove these:
rm -rf .claude/skills/langgraph-patterns
rm -rf .claude/skills/langchain-utilities
rm -rf .claude/skills/langsmith
```

The harness primitives (CLAUDE.md, hooks, subagents, commands, context management, evals) are stack-agnostic. Only the skills are stack-specific.

---

## Rollout Order

Don't install everything on day one. Order matters.

**Day 1.** Drop in `CLAUDE.md` and the four core hooks (`block-secrets`, `block-protected`, `format-on-write`, `tests-must-pass`). Use the harness on real work for a few days. See what hurts.

**Day 2.** Add `inject-context.sh` and the context management skill. Add the three subagents and the slash commands.

**Day 3.** Add the skills relevant to your stack. Don't blanket-install — import only the ones that match work you actually do.

**Day 4.** Build the eval harness. Write 3-5 golden tasks based on real work. Set up the GitHub Action.

**Beyond.** Iterate based on what evals tell you. Add project-specific skills as patterns emerge. Adjust the compact threshold if 50% is too aggressive or too lax.

---

## File Reference

```
.
├── CLAUDE.md                              # Root instructions (~60 lines)
├── .gitignore                             # Ignores checkpoints, logs, caches, eval runs
├── docs/
│   ├── architecture.md                    # Three-layer architecture: API → Agent → Tools
│   ├── conventions.md                     # Naming, imports, types, errors, git, tests
│   └── plans/                             # Plan files for in-flight features
├── .claude/
│   ├── settings.json                      # Hook config + permission denylist
│   ├── checkpoints/                       # Session checkpoint files (gitignored)
│   ├── agents/
│   │   ├── explorer.md                    # Read-only repo navigator
│   │   ├── critic.md                      # Code reviewer
│   │   └── test-writer.md                 # Pytest test writer
│   ├── commands/
│   │   ├── plan.md                        # /plan — PRD interview
│   │   ├── build.md                       # /build — TDD implementation
│   │   ├── check.md                       # /check — code review
│   │   ├── score.md                       # /score — rubric scoring
│   │   └── clear-and-go.md                # /clear-and-go — context reset
│   ├── hooks/
│   │   ├── block-secrets.sh               # Blocks secret file access
│   │   ├── block-protected.sh             # Blocks protected path edits
│   │   ├── format-on-write.sh             # Auto-formats with ruff
│   │   ├── typecheck-on-write.sh          # Auto-typechecks with mypy
│   │   ├── tests-must-pass.sh             # Blocks turn if tests fail
│   │   └── inject-context.sh              # Injects git + checkpoint context
│   ├── skills/
│   │   ├── context-management/            # Proactive context hygiene (always loaded)
│   │   ├── prd-interview/                 # Structured PRD questions
│   │   ├── vertical-slice/                # Slice PRDs into shippable units
│   │   ├── fastapi-patterns/              # Thin API layer patterns
│   │   ├── pytest-tdd/                    # Test patterns and fixtures
│   │   ├── langgraph-patterns/            # Agent design patterns
│   │   ├── langchain-utilities/           # Chat models, routing, tools
│   │   ├── langsmith/                     # Production tracing and evals
│   │   ├── gcp-runtime/                   # Cloud Run, Secret Manager, CI
│   │   ├── gcp-state-and-events/          # Firestore checkpointer, Pub/Sub
│   │   ├── docker-compose/                # Local dev with emulators
│   │   └── eval-task/                     # Local eval format (manual)
│   └── logs/                              # Hook logs (gitignored)
├── evals/
│   ├── rubric.md                          # 10-item behavioral checklist
│   ├── run.py                             # Headless eval runner
│   ├── tasks/                             # Golden task files
│   └── runs/                              # Eval reports (gitignored)
└── .github/workflows/
    └── eval.yml                           # CI: runs evals on harness PRs
```

---

Built at AIMANA. Maintained as needed, not as theater.
