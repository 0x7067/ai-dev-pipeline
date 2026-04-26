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

## Multi-Language Support

Examples are provided for four languages, each demonstrating FC/IS layers, boundary parsing, error handling, property-based tests, contract tests, end-to-end scenarios, and anti-patterns:

| Language | Directory |
|---|---|
| Python | `examples/python/` |
| Go | `examples/go/` |
| Rust | `examples/rust/` |
| TypeScript | `examples/typescript/` |

All examples are stdlib-only and self-contained. The boundary check script (`scripts/check-boundary-violations.sh`) auto-detects project language from markers (`pyproject.toml`, `go.mod`, `Cargo.toml`, `package.json`) and applies the appropriate ingress regex.

## Workflow Enforcement

Workflow phase prerequisites are enforced by hook-based gates. Running `/implement` before `/plan` is blocked, `/review` and `/test` require `/implement`, and `/verify` requires `/test`.

- State is tracked in `.claude/workflow-state.json` (gitignored)
- Use `/reset` to clear all phase completions and start a new task
- Set `WORKFLOW_GATES_SKIP=1` to bypass all checks
- `/cycle` and `/autopilot` orchestrate internally and are not gated

## Proactive Invocation

Pipeline skills auto-engage based on intent — describing a bug, feature, review, refactor, or release triggers the matching skill before any other response. The `SessionStart` hook (`.claude/hooks/session-start.sh`) loads the `using-pipeline` meta-skill at session start, which carries the intent → skill mapping. Explicit slash commands (`/plan`, `/implement`, etc.) remain available and behave identically.

## CI / GitHub Actions

Three workflows ship in `.github/workflows/`:

| Workflow | Purpose |
|---|---|
| `claude.yml` | Responds to `@claude` mentions in issues and PRs to perform on-demand tasks |
| `claude-code-review.yml` | Automated Claude code review on opened/updated pull requests |
| `shellcheck.yml` | Runs ShellCheck across the repo on pull requests and pushes to `main` |

## Environment Variables

See [docs/env-vars.md](docs/env-vars.md) for the full reference.
