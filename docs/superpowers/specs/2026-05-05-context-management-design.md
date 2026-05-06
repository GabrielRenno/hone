# Context Management — Design Spec

## Problem

Long Claude Code sessions (2+ hours) degrade in quality as the context window fills. Past ~100k tokens, models start hallucinating, forgetting decisions, and re-exploring files they already read. Today Hone has no proactive context management — only a manual `/clear-and-go` command and reliance on Claude Code's built-in auto-compact at 95% capacity.

## Goals

- Keep effective context under ~100k tokens throughout long sessions
- Proactively prevent context pollution rather than reactively recovering from it
- Preserve decisions, state, and task progress across compacts
- Make this invisible to the user — no manual intervention required

## Non-goals

- Custom memory system beyond what Claude Code provides
- Token counting from hooks (not supported by Claude Code)
- Modifying Claude Code's compact algorithm

---

## Design

### 1. Auto-compact threshold

Set `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` so auto-compact triggers at ~50% context usage instead of the default 95%. For a 200k window, this fires at ~100k — right at the quality threshold.

**Where it lives:** Exported by `inject-context.sh` on every UserPromptSubmit. This ensures it's always set regardless of shell profile.

### 2. Compact Instructions in CLAUDE.md

Add a `## Compact Instructions` section to CLAUDE.md:

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

### 3. Checkpoint files

At natural phase transitions (after exploration, after implementation, after tests pass), Claude writes a state snapshot to `.claude/checkpoints/current.md`.

**Format:**

```markdown
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

**Lifecycle:**
- Overwritten (not appended) at each phase transition
- Not committed to git — it's a session scratchpad
- `.claude/checkpoints/` is gitignored
- Survives compacts because it's a file, not conversation state

**Injection:** `inject-context.sh` reads `.claude/checkpoints/current.md` if it exists and includes it in the prompt context. After a compact, Claude immediately has the full state snapshot.

### 4. Context-management skill

New skill at `.claude/skills/context-management/SKILL.md`. Always-loaded (broad description trigger). Teaches five behaviors:

1. **Default to subagents for noisy work.** Exploration, multi-file reads, test output analysis, log review — route through the `explorer` subagent or a fresh Agent call. Main context only gets the summary.

2. **Never read large files into main context.** If a file is >100 lines and you only need part of it, use `Read` with `offset`/`limit` for the relevant section. Don't read entire files when you need 20 lines.

3. **Write checkpoints at phase transitions.** After finishing exploration, after tests go green, after completing a slice — update `.claude/checkpoints/current.md`. Not every turn, just at natural save points.

4. **Prefer targeted tool calls.** Use `Grep` with specific patterns over broad reads. Use `Read` with `offset`/`limit` over full file reads. Use `Glob` to confirm a file exists before reading it.

5. **Summarize before continuing.** After a subagent returns results, write down the 2-3 key findings in your response before acting on them. This creates a compact record that survives compression.

### 5. Subagent output discipline

Update `explorer.md` and `critic.md` to return findings, not raw content.

**Explorer:** "Return findings, not raw file contents. Lead with the answer, then file paths with line numbers. The caller can read targeted sections if needed. Example: 'The Firestore checkpointer is at `tools/firestore_state.py:15-45`, implements `aput` and `aget_tuple`, uses async client' — not the 45 lines of source."

**Critic:** "If the diff is clean, say so in one line. Don't pad with context or positive observations. Report only actual issues."

**Test-writer:** No change — already produces focused output (test code + fixture notes).

---

## Files to create or modify

| File | Action |
|------|--------|
| `.claude/hooks/inject-context.sh` | Add `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50` export + checkpoint injection |
| `CLAUDE.md` | Add `## Compact Instructions` section |
| `.claude/skills/context-management/SKILL.md` | Create — always-loaded context hygiene skill |
| `.claude/agents/explorer.md` | Add output discipline: findings not raw content |
| `.claude/agents/critic.md` | Add output discipline: issues only, no padding |
| `.gitignore` | Add `.claude/checkpoints/` |

## Verification

1. Start a session, run `/plan` on a non-trivial idea — confirm subagent exploration stays concise
2. Run `/build` on a slice — confirm checkpoint file is written after exploration and after tests pass
3. Check that `inject-context.sh` output includes checkpoint content when the file exists
4. Run `/compact` manually — confirm decisions and file paths survive in the post-compact context
5. Verify `.claude/checkpoints/` is gitignored
