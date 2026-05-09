# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.13.0] - 2026-05-09

### Added

- HITL approval framework (run `20260509T161841-e8ab70-f6`):
  - `.claude/policy/approvals.yaml` — declarative approval policy, single
    source of truth for plan/release gate behavior, scope thresholds, and
    verb sets.
  - `scripts/parse-{status-line,approvals-policy,pending-approval}.sh` —
    typed boundary parsers, fail-closed on malformed input.
  - `scripts/lib/{hitl-core,decisions-core}.sh` — pure core: `policy_apply`
    (auto-approve fail-closed; emits `reject-reason=` on stderr),
    `risk_rationale_format`, `time_box_resolve` (monotonic),
    `refactor_scope_classify`, and a key-anchored byte-walking JSON-string
    parser for `decision_record_build`/`decision_record_parse` (round-trip
    safe under commas, embedded `":`, escapes).
  - `scripts/{append-decision,queue-pending-approval}.sh` — atomic JSONL
    appender (flock + tempfile fallback) and atomic pending-approval
    marker writer.
  - `docs/templates/{approvals-policy-template.yaml,decisions-jsonl-schema.md}`.
  - 5 new test suites under `tests/scripts/` covering invariants 1, 3, 4,
    5, 8 and accept/reject/round-trip on all four boundary parsers
    (bash 3.2 / macOS compatible).

### Changed

- Plan-gate verbs: `approve | edit | reject`; release-gate verbs:
  `approve | reject` only (HITL plan invariant 8). `/ship` step 7
  captures `policy_apply` stderr and forwards
  `reject-reason={verifier-crashed|gates-failed|smoke-failed}` as the
  audit-log rationale; allowlisted, falls back to `policy`.
- `/ship queue` mode + optional `time-box=<seconds>` modifier on halts;
  marker written atomically and read only via the typed parser.
- `/refactor` plan gate fires when scope > thresholds parsed from
  `approvals.yaml`.
- Every gate transition appends one record to `${RUN_DIR}/decisions.jsonl`
  per the new schema.
- `.claude/rules/decision-surfacing.md` — adds "Draft plan with open
  decisions / batch at plan gate" section. Co-landed with the
  `.claude/agents/planner.md` STATUS-shape change (`risk_reason=<phrase>`)
  per HITL plan invariant 7 (atomic Phase 2).
- `.claude/rules/release-and-verification.md` — points approval policy
  at `approvals.yaml`; references `policy_apply` and `decisions.jsonl`;
  adds `/ship queue` to the legal mode set.
- Lean-path smoke gate: `scripts/smoke-bootstrap.sh` defaults
  `REPORT_QUALITY_PHASE=pre-release` and `REPORT_TEST_OPTIONAL=1` so the
  lean `/ship` path (no tester phase, release decision pending) passes
  cleanly. `scripts/check-report-quality.sh` parses both env vars
  through a typed allowlist and accepts `pending` for "Release approved"
  only when phase is `pre-release`.
- Bumped plugin/marketplace version to `0.13.0`.

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
