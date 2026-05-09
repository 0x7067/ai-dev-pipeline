# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2026-05-09

### Added

- `scripts/lib/style.sh`: capability-aware shell style library (color, unicode,
  optional `gum` rendering) with idempotent guard and a single source of truth
  for glyphs used by gate runners and orchestrator banners.
- `.claude/rules/output-style.md`: glyph legend, capability env-var contract,
  FC/IS placement (shell-only), and hard rules forbidding ANSI in committed
  markdown.

### Changed

- Bumped plugin/marketplace version to `0.12.0`.

## [0.11.0] - 2026-05-09

### Added

- `latest-green` pointer + manifest-aware smoke gate (v1.b): promote a run to
  `docs/latest-green` only when verify is green and review has zero blocking
  findings; smoke gate consults the run manifest to choose targets.
- Per-run `manifest.json` writer + parser (v1.a): every run records inputs,
  artifacts, and gate outcomes so downstream skills can consume a typed
  manifest instead of re-deriving state from filesystem layout.

## [0.10.0] - 2026-05-09

### Breaking

- Simplified `/ship` to the lean flow: optional research, plan, implement,
  review, verify, smoke, release.
- Replaced `/ship fast` with default `/ship auto`. Legacy `/ship fast` and
  `/ship adaptive` are rejected instead of aliased.
- Removed the mandatory TDD pre-phase from `/ship`. Tests now run through the
  verifier's canonical gate runner, with optional standalone test artifacts.
- Removed config-only review folding and narrowed verification branches. The
  default path always produces a normal review report and verify report.

### Changed

- Medium/high-risk runs still require plan approval. Low-risk runs continue
  automatically unless `/ship strict` is used.
- Release auto-approval now has one condition set: mode `auto`, low risk,
  no blocking review findings, green verification, and passing smoke.
- `scripts/check-workflow-artifacts.sh` no longer requires `test-report.md`
  unless one exists, matching the lean `/ship` flow.
- `scripts/check-workflow-artifacts.sh` resolves artifacts from `RUN_DIR`,
  then `docs/latest`, then legacy `docs/*.md`.

## [0.9.0] - 2026-05-09

Prior simplification release; superseded by `0.10.0`.

## [0.8.0] - 2026-04

Prior release; see git history.
