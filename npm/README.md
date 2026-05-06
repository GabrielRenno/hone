# create-hone

Scaffold a [Hone](https://github.com/GabrielRenno/hone) harness for Claude Code into your project.

## Usage

```bash
npx create-hone@latest
```

Run this from your project root. It copies the harness files (`.claude/`, `docs/`, `evals/`, `CLAUDE.md`), makes hooks executable, and merges `.gitignore` entries. It won't overwrite existing files.

## What is Hone?

A Claude Code harness that enforces discipline for shipping production agents — tight TDD, blocked secrets, automatic formatting, proactive context management, and a structured plan-build-check-score workflow.

See the [full documentation](https://github.com/GabrielRenno/hone) for details.

## Publishing

```bash
cd npm
npm publish
```
