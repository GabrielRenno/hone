---
name: vertical-slice
description: Cuts a PRD into vertical slices — independently shippable, testable, reversible units of work. Auto-loads after a PRD exists and the user asks about implementation order or wants to start building.
---

# Vertical Slice

A vertical slice is a piece of work that:
- Touches every layer it needs to (router → service → repo → migration if applicable)
- Has working tests at the end
- Can ship to main on its own without breaking anything
- Is reversible — could be reverted in a single commit

## Process

1. **Read the PRD** at `docs/plans/<slug>.md`.

2. **Cut it into 3–7 slices.** Each slice represents a few hours of work. If a slice would take a full day, cut it smaller. If a slice is under 30 minutes, merge it with another.

3. **Order them.** First slice should produce something visible end-to-end, even if narrow (the "happy path with no edge cases" version). Later slices add edge cases, error handling, performance, observability.

4. **Append slices to the PRD** under a `## Slices` section. Format:

```markdown
## Slices

### Slice 1 — <name>
- Scope: <what's in>
- Out of scope: <what's deferred>
- Acceptance: <test that must pass>

### Slice 2 — <name>
...
```

5. **Optionally write to ClickUp.** If the user has the ClickUp MCP connected and asks for it, create a task per slice with the same content.

## The shipping rule

If a slice can't go to main without breaking something, it's not a vertical slice — it's a partial implementation. Re-cut it.
