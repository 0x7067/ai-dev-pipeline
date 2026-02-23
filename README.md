# ai-dev-pipeline

A reusable Claude Code workflow plugin for structured AI-assisted development. Enforces Functional Core / Imperative Shell (FC/IS) architecture, strict boundary parsing, and human approval checkpoints.

## Installation

Install via the Claude Code plugin system, then run `/setup` in any project to scaffold scripts, rules, and templates.

## Commands

| Command | Description |
|---|---|
| `/setup` | Scaffold project-level artifacts (scripts, templates, rules, CI) into the current repo |
| `/plan` | Analyze requirements and produce an implementation plan |
| `/research` | Perform upfront research for unclear or high-risk work |
| `/implement` | Implement changes from the approved plan |
| `/review` | Severity-first architecture, security, and correctness review |
| `/audit` | Holistic project audit — structure, conventions, critical issues, and quick wins |
| `/test` | Generate and run tests including property-based and boundary contract tests |
| `/verify` | Run verification gates and produce a go/no-go decision |
| `/cycle` | Run full workflow: plan → implement → review → test → verify |
| `/autopilot` | Same as `/cycle` with optional research and approval gates |

`/review` is a **merge gate** — operates on code changes, produces blocking/warning/advisory findings. `/audit` is a **project health check** — reviews the whole project periodically or before major architectural decisions.

## Workflow

```
/plan → /implement → /review → /test → /verify
```

Use `/cycle` to orchestrate all phases, or `/autopilot` to include optional research with approval gates at risk checkpoints.

## Environment Variables

See [docs/env-vars.md](docs/env-vars.md) for the full reference.
