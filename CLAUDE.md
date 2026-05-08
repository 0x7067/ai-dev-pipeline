# CLAUDE.md

This repository contains a reusable Claude Code workflow baseline designed for multi-project reuse.

## Workflow Goals
- Keep architecture deterministic and testable using Functional Core / Imperative Shell (FC/IS).
- Enforce strict boundary parsing: parse external data into trusted domain values before core logic.
- Use lightweight formal verification by default: property-based tests + contract tests.
- Run deterministic quality checks through hooks and validation scripts.
- Keep human-in-the-loop control points explicit for planning, high-risk changes, and release.
- Keep evidence quality high: official docs first, limited external sources, no unsourced numeric claims.

## Default Command Flow

The slash-command picker exposes exactly five primary entries:

- `/ship` — orchestrates the full per-change pipeline (research → plan → implement → review → test → verify → smoke → release) with risk-adaptive approval gates by default. Pass `/ship strict` for unconditional plan approval.
- `/review` — review existing code, a diff, or a PR (standalone severity-first review).
- `/refactor` — behavior-preserving structural change with pre/post verification gates.
- `/audit` — holistic project audit (structure, conventions, critical issues, quick wins).
- `/research` — brainstorm, investigate, or get unstuck before any plan exists.

> Other phase logic (planning, implementation, testing, verification, setup, reset) remains reachable via skills and agents (e.g. `requirement-analysis`, `test-gen`, `static-analysis`, `setup`, `reset`). See `.claude/skills/using-pipeline/SKILL.md` for the intent → entry-point mapping.

> Migration: `/cycle` and `/autopilot` were merged into `/ship`. `/ship` defaults to the previous `/autopilot` (risk-adaptive) behavior; `/ship strict` reproduces the previous `/cycle` behavior.

## Proactive Invocation
When the user describes a coding intent — fixing a bug, adding a feature, reviewing, refactoring, shipping — Claude must invoke the matching pipeline skill, command, or agent **proactively**, before producing any other response, rather than waiting for an explicit slash command. The `using-pipeline` meta-skill (`.claude/skills/using-pipeline/SKILL.md`) is the source of truth for intent → skill mapping and the anti-rationalization rules; it is auto-loaded at session start by the `SessionStart` hook in `.claude/hooks/session-start.sh`.

## Reuse Contract
- Keep tooling detection dynamic: scripts should auto-detect `bun`, `npm`, `pnpm`, `yarn`, or project-native commands.
- Keep policies centralized in `.claude/rules/`.
- Keep agent/skill wiring validated by `scripts/validate-claude-config.sh`, which also runs `scripts/check-plugin-version-sync.sh` to keep `plugin.json` and `.claude-plugin/plugin.json` versions in sync.
- Treat this folder as a template that can be copied into new projects.
- Reuse report and assessment templates from `docs/templates/` for consistent outputs.

## Rules
@.claude/rules/code-style.md
@.claude/rules/architecture-fcis.md
@.claude/rules/boundary-parse-dont-validate.md
@.claude/rules/testing-formal-lite.md
@.claude/rules/security-baseline.md
@.claude/rules/release-and-verification.md
