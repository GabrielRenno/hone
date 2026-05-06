---
name: prd-interview
description: Interviews the user to turn an idea into a written PRD. Auto-loads when the user says "new feature", "build something that", "I want to add X", or any phrasing that introduces a feature without a written spec.
---

# PRD Interview

Your job is to turn an idea into a written PRD that can drive a TDD implementation loop.

## Process

1. **Restate the idea.** In one sentence, what's being built. Confirm with the user before continuing.

2. **Ask 15–30 questions, one at a time.** Cover:
   - Who triggers this? (User, system, scheduled)
   - What's the input shape?
   - What's the output shape?
   - What are the non-trivial edge cases? (Empty input, duplicates, partial failure, concurrency)
   - What happens on error? (Rollback, partial commit, retry)
   - What does success look like? (Specific, measurable)
   - What's explicitly out of scope?
   - Any existing code this touches or replaces?

3. **Don't ask about implementation.** No questions about library choice, schema design, or architecture. Those belong in the implementation step.

4. **Write the PRD** to `docs/plans/<slug>.md` with this structure:

```markdown
# <Feature name>

## Goal
One paragraph. What this does and why.

## Non-goals
What this explicitly does NOT do. Three to five bullets.

## Inputs and outputs
Function signatures or endpoint shapes. Pydantic models if relevant.

## Acceptance criteria
A bulleted list. Each item is a specific, testable behavior.

## Edge cases
What weird things must be handled. How.

## Out of scope
Things you considered and decided not to do. With reasons.
```

5. **Confirm.** Show the user the PRD path and the first few sections. Ask if anything's missing before they run `/build`.

## Don't

- Don't write any code in this step.
- Don't propose vertical slices yet — that's the next skill.
- Don't pad the PRD with boilerplate sections that aren't needed for the specific feature.
