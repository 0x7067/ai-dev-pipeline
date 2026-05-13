# CLAUDE.md

This repository contains a reusable Claude Code workflow baseline designed for multi-project reuse.

## Workflow Goals
- Keep architecture deterministic and testable using Functional Core / Imperative Shell (FC/IS).
- Enforce strict boundary parsing: parse external data into trusted domain values before core logic.
- Use lightweight formal verification when it exists; the default `/ship` path does not create a separate TDD phase.
- Run deterministic quality checks through hooks and validation scripts.
- Keep human-in-the-loop control points explicit for planning, high-risk changes, and release.
- Keep evidence quality high: official docs first, limited external sources, no unsourced numeric claims.

## Default Command Flow

The slash-command picker exposes exactly five primary entries:

- `/ship` — orchestrates the per-change pipeline (optional research → plan → implement → review → verify → smoke → release). Low-risk green runs auto-finish; pass `/ship strict` for explicit approvals.
- `/review` — review existing code, a diff, or a PR (standalone severity-first review).
- `/refactor` — behavior-preserving structural change with pre/post verification gates.
- `/audit` — holistic project audit (structure, conventions, critical issues, quick wins).
- `/research` — brainstorm, investigate, or get unstuck before any plan exists.

> Other phase logic (planning, implementation, testing, verification, setup, reset) remains reachable via skills and agents (e.g. `requirement-analysis`, `test-gen`, `static-analysis`, `setup`, `reset`). See `.claude/skills/using-pipeline/SKILL.md` for the intent → entry-point mapping.

> Migration: `/cycle`, `/autopilot`, `/ship fast`, and `/ship adaptive` are legacy. Use `/ship`, `/ship strict`, or `/ship research <topic>`.

## Proactive Invocation
When the user describes a coding intent — fixing a bug, adding a feature, reviewing, refactoring, shipping — Claude must invoke the matching pipeline skill, command, or agent **proactively**, before producing any other response, rather than waiting for an explicit slash command. The `using-pipeline` meta-skill (`.claude/skills/using-pipeline/SKILL.md`) is the source of truth for intent → skill mapping and the anti-rationalization rules; it is auto-loaded at session start by the `SessionStart` hook in `.claude/hooks/session-start.sh`.

## Reuse Contract
- Keep tooling detection dynamic: scripts should auto-detect `bun`, `npm`, `pnpm`, `yarn`, or project-native commands.
- Keep policies centralized in `.claude/rules/`.
- Keep agent/skill wiring validated by `scripts/validate-claude-config.sh`, which also runs `scripts/check-plugin-version-sync.sh` to keep `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions in sync.
- Treat this folder as a template that can be copied into new projects.
- Reuse report and assessment templates from `docs/templates/` for consistent outputs.

### Project Root
`AIDP_PROJECT_ROOT` is the canonical anchor for run artifacts; `AIDP_ARTIFACTS_ROOT` is the subdirectory that actually holds them. Both are exported once at the top of `/ship`, derived by the boundary parser at `scripts/lib/project-root.sh`:

- `AIDP_PROJECT_ROOT` ← `CLAUDE_PROJECT_DIR` (fallback `$(pwd)`), canonicalized.
- `AIDP_ARTIFACTS_ROOT` ← `${AIDP_PROJECT_ROOT}/docs/aidp` unconditionally, for every caller.

Run artifacts (`runs/<id>/…`, `latest`, `latest.txt`, `latest-green.txt`) live under `AIDP_ARTIFACTS_ROOT`. The workflow-state pointer (`.claude/workflow-state/active`) stays under `AIDP_PROJECT_ROOT` since it is already namespaced. Helper scripts (`mint-run-id.sh`, `prune-runs.sh`, `smoke-bootstrap.sh`) consume the parsed values; `RUN_DIR` must be absolute. This keeps the top-level `docs/` clean for checked-in plugin documentation (`docs/templates/`, `docs/specs/`, `docs/schemas/`, `docs/reference/`, `docs/superpowers/`).

## Rules
@.claude/rules/code-style.md
@.claude/rules/architecture-fcis.md
@.claude/rules/boundary-parse-dont-validate.md
@.claude/rules/testing-formal-lite.md
@.claude/rules/security-baseline.md
@.claude/rules/release-and-verification.md
@.claude/rules/decision-surfacing.md
@.claude/rules/output-style.md
