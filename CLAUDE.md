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
1. `/plan`
2. `/implement`
3. `/review`
4. `/test`
5. `/verify`
6. `/cycle` (orchestrates all phases)

## Reuse Contract
- Keep tooling detection dynamic: scripts should auto-detect `bun`, `npm`, `pnpm`, `yarn`, or project-native commands.
- Keep policies centralized in `.claude/rules/`.
- Keep agent/skill wiring validated by `scripts/validate-claude-config.sh`.
- Treat this folder as a template that can be copied into new projects.
- Reuse report and assessment templates from `docs/templates/` for consistent outputs.

## Rules
@.claude/rules/code-style.md
@.claude/rules/architecture-fcis.md
@.claude/rules/boundary-parse-dont-validate.md
@.claude/rules/testing-formal-lite.md
@.claude/rules/security-baseline.md
@.claude/rules/release-and-verification.md
