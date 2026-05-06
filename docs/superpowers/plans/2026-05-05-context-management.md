# Context Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add proactive context management to Hone so long sessions stay under ~100k tokens without manual intervention.

**Architecture:** Five pieces working together — lower auto-compact threshold, compact instructions in CLAUDE.md, checkpoint files written at phase transitions and injected by hook, a context-management skill teaching subagent-first behavior, and tighter output discipline on existing subagents.

**Tech Stack:** Bash (hooks), Markdown (skill, CLAUDE.md, checkpoint format), gitignore.

**Spec:** `docs/superpowers/specs/2026-05-05-context-management-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `.gitignore` | Modify | Add `.claude/checkpoints/` |
| `.claude/hooks/inject-context.sh` | Modify | Export compact threshold + inject checkpoint |
| `CLAUDE.md` | Modify | Add Compact Instructions section |
| `.claude/skills/context-management/SKILL.md` | Create | Always-loaded context hygiene behaviors |
| `.claude/agents/explorer.md` | Modify | Add output discipline paragraph |
| `.claude/agents/critic.md` | Modify | Add output discipline paragraph |

---

### Task 1: Gitignore checkpoint directory

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add checkpoint directory to gitignore**

Add `.claude/checkpoints/` to `.gitignore`:

```
.claude/checkpoints/
```

Append it after the existing `.claude/logs/` line.

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore checkpoint directory"
```

---

### Task 2: Update inject-context.sh — compact threshold + checkpoint injection

**Files:**
- Modify: `.claude/hooks/inject-context.sh`

- [ ] **Step 1: Add compact threshold export**

Add this line near the top of the script, after `set -euo pipefail`:

```bash
# Trigger auto-compact at 50% context usage (~100k tokens) to prevent quality degradation.
export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
```

- [ ] **Step 2: Add checkpoint injection**

After the `PLANS` block (the `if [[ -d "docs/plans" ]]` section) and before the `cat << CTX` heredoc, add:

```bash
CHECKPOINT=""
if [[ -f ".claude/checkpoints/current.md" ]]; then
  CHECKPOINT=$(cat .claude/checkpoints/current.md 2>/dev/null || true)
fi
```

Then update the heredoc to include the checkpoint:

```bash
cat << CTX
<git-context>
Branch: $BRANCH
Recent commits:
$COMMITS
$PLANS
</git-context>
CTX

if [[ -n "$CHECKPOINT" ]]; then
  cat << CKPT
<session-checkpoint>
$CHECKPOINT
</session-checkpoint>
CKPT
fi
```

- [ ] **Step 3: Verify the hook runs without errors**

```bash
echo '{}' | bash .claude/hooks/inject-context.sh
```

Expected: Output includes `<git-context>` block. No `<session-checkpoint>` block (because no checkpoint file exists yet).

- [ ] **Step 4: Test with a checkpoint file present**

```bash
mkdir -p .claude/checkpoints
echo "# Checkpoint — test" > .claude/checkpoints/current.md
echo '{}' | bash .claude/hooks/inject-context.sh
rm .claude/checkpoints/current.md
rmdir .claude/checkpoints
```

Expected: Output includes both `<git-context>` and `<session-checkpoint>` blocks.

- [ ] **Step 5: Commit**

```bash
git add .claude/hooks/inject-context.sh
git commit -m "feat: inject-context exports compact threshold and injects checkpoint state"
```

---

### Task 3: Add Compact Instructions to CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add Compact Instructions section**

Add the following section at the end of `CLAUDE.md`, after the "When you don't know something" section:

```markdown

## Compact Instructions
When compacting this conversation, always preserve:
- The current slice being worked on and its acceptance criteria
- All decisions made (architecture choices, trade-offs, rejected alternatives) and their reasoning
- File paths that have been modified or are relevant to the current task
- Current test state (what's passing, what's failing, what's left to write)
- Any user preferences or corrections expressed during this session
- The checkpoint file path if one exists (read it for full state)

Discard:
- Raw file contents that were read for exploration (the files still exist on disk)
- Verbose tool output (test logs, git diffs, grep results)
- Intermediate reasoning that led to decisions already captured above
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "feat: add compact instructions to preserve decisions and discard noise"
```

---

### Task 4: Create context-management skill

**Files:**
- Create: `.claude/skills/context-management/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p .claude/skills/context-management
```

- [ ] **Step 2: Write the skill file**

Create `.claude/skills/context-management/SKILL.md` with the following content:

```markdown
---
name: context-management
description: Proactive context hygiene for long sessions. Auto-loads on every task — keeps main context lean by routing noisy work through subagents, writing checkpoints at phase transitions, and preferring targeted reads over full file dumps.
---

# Context Management

Long sessions degrade past ~100k tokens. These rules keep the main context lean without losing information.

## 1. Route noisy work through subagents

Exploration, multi-file reads, test output analysis, and log review go through the `explorer` subagent or a fresh Agent call. The main context only sees the summary.

**Do:**
- Use `explorer` to map out a subsystem, then act on the file paths it returns
- Use a subagent to read and analyze test output, then get back a pass/fail summary
- Use a subagent to search for patterns across many files

**Don't:**
- Read 5+ files into main context to "understand the codebase"
- Dump full test output into main context when you only need the failing test name
- Grep broadly and read every match — let a subagent triage first

## 2. Read targeted sections, not full files

If a file is over ~100 lines and you only need part of it, use `Read` with `offset` and `limit` for just the relevant section. Use `Grep` first to find the line numbers you need.

**Pattern:**
1. `Grep` for the function/class name → get line number
2. `Read` with `offset` and `limit` → get the 20-50 lines you need
3. Act on what you read

**Exception:** Files under ~100 lines can be read in full — the cost is negligible.

## 3. Write checkpoints at phase transitions

After completing a major phase, write a state snapshot to `.claude/checkpoints/current.md`. This file is injected into every prompt by the inject-context hook, so it survives compacts and context resets.

**When to write a checkpoint:**
- After finishing exploration (you now know what to build)
- After tests go green on a slice
- After completing a slice before starting the next
- Before any operation that might trigger a compact (large subagent dispatch, many tool calls)

**Checkpoint format:**

```
# Checkpoint — <ISO timestamp>

## Active slice
<slice name and acceptance criteria>

## Decisions made
<bulleted list of key decisions with reasoning>

## Files modified
<list of paths created/changed>

## Test state
<what's passing, what's failing>

## What's next
<immediate next step>
```

Overwrite the file each time — it's a snapshot, not a log.

## 4. Prefer targeted tool calls

- `Grep` with specific patterns over broad reads
- `Read` with `offset`/`limit` over full file reads
- `Glob` to confirm a file exists before reading it
- `Bash` with `| head -20` or `| tail -20` for command output that might be long

## 5. Summarize before continuing

After a subagent returns results, write down the 2-3 key findings in your response text before acting on them. This creates a compact, human-readable record that survives compression better than raw tool output.

**Pattern:**
- Subagent returns: "Found 3 relevant files..."
- You write: "The classifier lives in `app/agents/classifier/nodes.py:15-45`, uses structured output, and routes via `edges.py:10`. I'll start with the node."
- Then act.

This costs a few tokens now but saves hundreds of tokens later because the compact retains your summary instead of the subagent's full output.
```

- [ ] **Step 3: Verify the skill file is valid**

```bash
head -4 .claude/skills/context-management/SKILL.md
```

Expected: YAML frontmatter with `name: context-management` and `description:` on the first lines.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/context-management/SKILL.md
git commit -m "feat: add context-management skill for proactive context hygiene"
```

---

### Task 5: Update subagent output discipline

**Files:**
- Modify: `.claude/agents/explorer.md`
- Modify: `.claude/agents/critic.md`

- [ ] **Step 1: Add output discipline to explorer**

Add the following paragraph to `explorer.md`, at the end of the "Output format:" section (before the "Do not:" section):

```markdown
Context discipline:
- Return findings, not raw file contents. The caller can read targeted sections if needed.
- Good: "The Firestore checkpointer is at `tools/firestore_state.py:15-45`, implements `aput` and `aget_tuple`, uses async client."
- Bad: pasting the 45 lines of source code into the response.
- When mapping a subsystem, return the structure summary — not the contents of every file.
```

- [ ] **Step 2: Add output discipline to critic**

Add the following line to `critic.md`, at the end of the "Output format:" section (after the "If nothing is wrong, say so directly." line):

```markdown
- Keep findings concise. If the diff is clean, say so in one sentence — don't pad with context summaries or positive observations.
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/explorer.md .claude/agents/critic.md
git commit -m "feat: add output discipline to explorer and critic subagents"
```

---

## Verification

After all tasks are complete, verify end-to-end:

- [ ] `.claude/checkpoints/` is in `.gitignore`
- [ ] `echo '{}' | bash .claude/hooks/inject-context.sh` outputs `<git-context>` block and exports `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`
- [ ] Creating a checkpoint file at `.claude/checkpoints/current.md` and re-running the hook shows it in `<session-checkpoint>` block
- [ ] `CLAUDE.md` has a `## Compact Instructions` section
- [ ] `.claude/skills/context-management/SKILL.md` exists with valid frontmatter
- [ ] `explorer.md` contains "Context discipline" section
- [ ] `critic.md` contains "Keep findings concise" line
