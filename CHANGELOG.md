# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `release` skill resume contract now dispatches from the state file's
  recorded `phase` rather than the undocumented `RELEASE_PHASE` env var.
  Previously, re-entering with `RELEASE_RESUME=1 RELEASE_ANSWER=approve`
  after the push-confirm halt re-ran Phase B and errored with
  `tag already exists`. New typed boundary parser
  (`scripts/release/parse-release-state.sh`) and pure core dispatcher
  (`scripts/release/lib/resume-core.sh`) make the resume path total
  and deterministic. Two new contract tests
  (`test-release-resume-phase-b-complete-{approve,reject}.sh`).

## [0.16.0] - 2026-05-10

### Added

- New `release` skill (`.claude/skills/release/SKILL.md`) automating the
  version-bump → gates → manifest sync → CHANGELOG rewrite → commit → tag →
  push sequence. Skill-only (no slash command). Halts twice for explicit
  human approval (proposed version, push). Triggers on "cut a release",
  "bump tag", "tag v…", "ship a release", "release this".
- Pure FC core: `scripts/release/lib/semver-core.sh` (SemVer parser +
  `next_version` + `compare_semver`) and `scripts/release/lib/changelog-core.sh`
  (`infer_bump_from_changelog`).
- Boundary parser at `scripts/release/parse-changelog.sh` (typed records;
  rejects malformed headers, unknown labels, duplicate version sections).
- Five tests cover the new surface: changelog accept/reject, SemVer
  property (monotonicity + round-trip), 3-file lockstep contract,
  ERR-trap rollback on Phase B mutation failure, and boundary parse of
  `RELEASE_STATE_FILE` on resume.

### Fixed

- `CLAUDE.md` no longer references a non-existent root `plugin.json`; the
  version-sync check runs between `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` only.

## [0.15.1] - 2026-05-10

### Changed

- Persistent feature specs now live at `docs/specs/<id>/spec.yaml` (one
  directory per spec, parsed via `scripts/specs/parse-spec.sh`).
  Supersedes the `docs/artifacts/specs/<feature>.md` location announced in
  `[0.15.0]` — that path no longer exists in the tree (INV-6 enforced by
  `tests/scripts/test-specs-layout.sh`). The new shape ships with a typed
  boundary parser, a static HTML renderer (`scripts/specs/render-html.sh`),
  and the index at `docs/specs/index.yaml`.

### Fixed

- `parse-spec.sh` now treats `boundary_map` as a required (possibly-empty)
  list, matching the schema declared in the parser comments.
- `parse_spec_index` rejects an index containing two items with the same
  `id` value (`tests/scripts/test-spec-parser.sh` reject-set).
- `render-html.sh` parses each `spec.yaml` exactly once per render — the
  index pass reads the typed records captured during the per-spec pass
  rather than re-invoking the parser. Output bytes are unchanged
  (INV-4 idempotence test still passes).
- `render-html.sh` short-circuits explicitly when no specs are present;
  removes the `${arr[@]:-}` `set -u` workaround.

### Docs

- Loose top-level reference docs (`env-vars.md`, `harness-engineering.md`,
  `hook-recipes.md`, `pragmatic-tips-mapping.md`, and the former
  `verification/acceptance-checklist.md`) are grouped under
  `docs/reference/`. The empty `docs/verification/` directory is removed.
  Inbound links in `README.md`, `scripts/smoke-bootstrap.sh`, and the
  `pragmatic-review-checklist` skill are updated. New `docs/.gitignore`
  ignores `.DS_Store` and `.verify-retry.json`.
- `.claude/scheduled_tasks.lock` is now gitignored.

## [0.15.0] - 2026-05-10

### Added

- SPDD selective borrows (run `20260510T150529-666528-5b`), informed by
  Fowler's *Structured Prompt-Driven Development*
  (https://martinfowler.com/articles/structured-prompt-driven). No
  paradigm pivot: the five-command surface and tool-derived gate
  authority are preserved.
  - Persistent feature specs at `docs/artifacts/specs/<feature>.md`.
    Egress-only this run; the planner mirrors the per-run spec when one
    is produced. A typed boundary parser is required before any agent
    reads from the tree (deferred to a future plan — SPDD borrow #2,
    code→spec sync).
  - Plan template gains optional `## Norms applied` and
    `## Safeguards applied` sections (links-only, flat list). The
    validator lints both as bare `.claude/rules/*.md` paths or markdown
    links targeting the same; non-link prose is rejected.
  - `<invest-mode>` in `.claude/agents/researcher.md`: always-on
    INVEST decomposition when the topic looks story-shaped. Conservative
    heuristic — requires `i want` + `so that`, OR `as a <role>`. Output
    on the non-trigger path is byte-identical (no banner, no mode flag).
  - `using-pipeline` SKILL gains a "Command surface stability"
    subsection that names the five commands and explicitly rejects a
    `/spdd-*` rename.
  - `.gitignore` allowlist extended to track `docs/artifacts/specs/**`.

## [0.14.0] - 2026-05-10

### Added

- Tier A UX polish (run `20260510T010654-8f5623-59`):
  - `style::hyperlink` emitter in `scripts/lib/style.sh` with internal
    readonly flag `STYLE_HYPERLINKS` (derived from `STYLE_COLOR=1` AND
    `[ -t 1 ]`; no new env var). `style::strip_ansi` now strips OSC-8 in
    addition to CSI/SGR.
  - Per-phase elapsed-time annotations on `/ship`, `/review`, `/refactor`
    banners (`✓ <phase> ok (Ns)`).
  - `scripts/{parse,append}-phase-timings.sh` and
    `scripts/render-end-of-run.sh`: incremental `phase_timings.json`
    writer, typed boundary parser, and shared end-of-run renderer.
  - `docs/schemas/phase-timings/v1/schema.json`: ordered-array schema for
    `phase_timings.json` (`schema_version`, `phases[]`, `total_seconds`).
  - End-of-run summary: failure summary (with last-20-line log preview)
    above the timing strip and decision trail; artifact paths wrapped via
    `style::hyperlink` on capable terminals.
  - Two-line plan-halt grammar in `/ship` (line 2 carries
    `risk=<tier> because <reason>`).

### Changed

- Approval halts (`/ship` plan + release gates, `/refactor` plan gate) now
  use `AskUserQuestion` instead of prose `reply "approve" / "edit
  <comment>" / "reject"` instructions. Each option's `description` carries
  the consequence in plain language.
- `.claude/rules/decision-surfacing.md`: added the Open-Decisions ⇔
  AskUserQuestion pairing rule and the "approval halts use
  AskUserQuestion" rule. Both enforced by
  `scripts/validate-claude-config.sh` (pure bash, no new dependency).
- `.claude/rules/output-style.md`: Glyph Legend (invariant I5) extended
  with `style::hyperlink`.

### Tests

- `tests/style/hyperlink_capability.sh`,
  `tests/style/strip_ansi_osc8.sh`,
  `tests/parse-phase-timings.sh`,
  `tests/validator/open-decisions-pairing.sh` — all green.

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

## [0.8.0] - 2026-04-01

Prior release; see git history.
