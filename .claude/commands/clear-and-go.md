---
description: Reset context and pick up at a specific slice without losing momentum.
---

The user is running this to clear their context window and continue work on:

$ARGUMENTS

Process:
1. Acknowledge the reset.
2. Read `docs/plans/<slug>.md` if a slug was given. If a specific slice ID was given, focus on that slice's section.
3. Read the current state of files referenced in the slice (test files, source files).
4. Show a one-paragraph summary of where things stand: which slices are done, which is next, what tests currently pass.
5. Wait for the user's next instruction. Do not start coding unless asked.

This command exists because plain `/clear` loses too much context for an in-progress feature. The plan file is the persistent memory; this command rehydrates from it.
