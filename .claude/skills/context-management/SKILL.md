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
