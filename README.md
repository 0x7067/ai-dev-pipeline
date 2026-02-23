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

### `/review` vs `/audit`

`/review` is a **merge gate** — operates on code changes, produces blocking/warning/advisory findings per feature. Run it before merging.

`/audit` is a **project health check** — reviews the project as a whole across structure, conventions, and design philosophy. Run it periodically or before major architectural decisions.

## Workflow

Default sequence:

```
/plan → /implement → /review → /test → /verify
```

Use `/cycle` to orchestrate all phases in one command, or `/autopilot` to include optional research with approval prompts at risk checkpoints.

## Architecture

This plugin enforces **Functional Core / Imperative Shell**:

- **Core** — pure business logic, no I/O, deterministic
- **Shell** — orchestration, side effects, I/O
- **Boundary** — parses untrusted external input into typed domain values before forwarding to core

All agents and scripts enforce these boundaries. Boundary violations are **blocking** findings in `/review`.

## Agents

| Agent | Role |
|---|---|
| `planner` | Produces `docs/current-plan.md` with FC/IS classification and risk tier |
| `researcher` | Upfront research for high-risk or unclear work |
| `implementer` | Implements from approved plan, enforcing FC/IS and parse-at-boundary |
| `reviewer` | Severity-first code review (blocking / warning / advisory) |
| `auditor` | Holistic project audit across 5 angles, read-only |
| `tester` | Property-based and boundary contract tests |
| `verifier` | Deterministic verification gates, go/no-go decision |

## Environment Variables

| Variable | Purpose |
|---|---|
| `HOOKS_FAST` | Skip slow hook checks (lint, type-check) in development |
| `BOUNDARY_CHECK_STRICT` | Fail on any boundary violation (default: warn) |
| `BOUNDARY_SRC_DIRS` | Source directories for boundary violation scanning |
| `BOUNDARY_INGRESS_REGEX` | Regex identifying ingress points (default targets JS/TS) |
| `BOUNDARY_CORE_GLOB` | Glob pattern for core layer files |
| `BOUNDARY_DOMAIN_GLOB` | Glob pattern for domain type files |
| `REPORT_QUALITY_REQUIRE_CONTENT` | Require non-empty report sections in smoke gate |
| `SECURITY_SCAN_REQUIRED` | Fail pipeline if security scan is skipped |

For the full variable reference, including `WORKFLOW_*` path overrides, see [docs/env-vars.md](docs/env-vars.md).
