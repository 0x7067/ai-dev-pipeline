# ai-dev-pipeline

A Claude Code plugin that adds a structured development workflow with verification gates, human approval checkpoints, and architecture guardrails.

## What it does

Provides slash commands that guide code changes through a disciplined pipeline:

```
/plan → /implement → /review → /test → /verify
```

Or run the full cycle at once with `/cycle`.

Each phase is backed by a specialized agent (planner, implementer, reviewer, tester, verifier) and enforced by automated hooks that run type-checking, linting, and formatting on every edit.

## Key concepts

- **Functional Core / Imperative Shell** -- business logic stays pure and testable, side effects live at the edges
- **Parse at the boundary** -- all external data is parsed into typed domain values before reaching core logic
- **Verification gates** -- type checks, lints, security scans, property-based tests, and contract tests must pass before a change is considered done
- **Human-in-the-loop** -- plan approval required before implementation; elevated review for medium/high-risk changes

## Installation

```bash
claude plugin add 0x7067/ai-dev-pipeline
```

## Available commands

| Command | Description |
|---|---|
| `/plan` | Analyze requirements and produce an implementation plan |
| `/implement` | Execute the approved plan |
| `/review` | Severity-first code review (architecture, security, correctness) |
| `/test` | Generate property-based and contract tests |
| `/verify` | Run all verification gates and produce a go/no-go report |
| `/cycle` | Orchestrate the full pipeline end-to-end |
| `/research` | Investigate unclear or high-risk areas before planning |
| `/autopilot` | Run the full chain with approval gates |

## Hooks

Runs automatically during Claude Code sessions:

- **PreToolUse** -- protects critical files from accidental edits
- **PostToolUse** -- type-checks and lints after every file write
- **Stop** -- formats code when the agent stops

## Project structure

```
.claude/
  agents/       # Specialized agents (planner, implementer, reviewer, tester, verifier, researcher)
  commands/     # Slash command definitions
  hooks/        # Automated quality hooks
  rules/        # Architecture and code style policies
  skills/       # Reusable skills (FC/IS, code review, test gen, etc.)
scripts/        # Verification and validation shell scripts
docs/           # Templates, reports, and specs
```

## Using as a template

This repo is designed to be copied into other projects. The scripts auto-detect your package manager (`bun`, `npm`, `pnpm`, `yarn`) and the rules are generic enough to apply to any codebase.

## License

[MIT](LICENSE)
