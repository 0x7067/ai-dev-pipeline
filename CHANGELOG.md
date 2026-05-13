# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.18.0] - 2026-05-13

### Changed

- **Unify on `docs/aidp/` for every caller — no plugin self-dev exception,
  no top-level `docs/` fallback.** `scripts/lib/project-root.sh::aidp_resolve_artifacts_root`
  now unconditionally returns `${root}/docs/aidp` for consumer projects
  AND for the plugin's own checkout. The `.claude-plugin/plugin.json`
  presence heuristic is gone; the resolver is now a pure string operation
  with no filesystem reads beyond canonicalization. `CLAUDE.md` and
  `.claude/rules/release-and-verification.md` state the single rule.

### Removed

- **`pragmatic-review-checklist` fallback to top-level `docs/review-report.md`.**
  The skill now fails closed when `RUN_DIR` is unset, matching the
  pattern in `code-review`, `refactor`, `requirement-analysis`, and
  `test-gen`.
- **Legacy plugin-self-dev branch in `aidp_resolve_artifacts_root`.** Tests
  that injected `.claude-plugin/plugin.json` to force the legacy path
  no longer need the injection (removed in `test-promote-latest-green.sh`
  and `test-run-id-end-to-end.sh`).

### Fixed

- **`scripts/validate-claude-config.sh`** now scans `docs/aidp/runs/` for
  current-plan.md files instead of the legacy `docs/runs/`.
- **`scripts/tests/test-project-root.sh`** updated: the "plugin checkout"
  case now asserts `docs/aidp` (no legacy exception) instead of the old
  `docs` return value.
- 12 affected test files migrated to `docs/aidp/runs/`, `docs/aidp/latest`,
  `docs/aidp/latest.txt` sandbox paths and assertions.
- Stale `docs/latest.txt` and `docs/.verify-retry.json` moved from the
  plugin checkout's top-level `docs/` to `docs/aidp/`.

## [0.17.1] - 2026-05-12

### Fixed

- **Eliminate top-level `docs/` leaks from skills and the planner agent.**
  In consumer repos the plugin was writing four artifact classes outside
  `${AIDP_ARTIFACTS_ROOT}` because skill prose and the planner's
  persistent spec mirror still referenced cwd-relative `docs/` paths
  introduced before the `AIDP_ARTIFACTS_ROOT` anchoring landed in 0.17.0:
  - Skill descriptions and output sections in `code-review`,
    `static-analysis`, `test-gen`, `refactor`, and
    `requirement-analysis` now reference `${RUN_DIR}/<report>.md`
    exclusively. The "falls back to `docs/<report>.md` when invoked
    outside a /ship-managed run" prose is removed; skills now fail
    closed if `RUN_DIR` is unset.
  - `.claude/agents/planner.md` — the `<persistent-spec-mirror>` block
    and the `write-allowed` constraint now use
    `${AIDP_ARTIFACTS_ROOT}/specs/<feature>/...` everywhere
    (`spec.yaml`, `spec.md`, `index.yaml`). The `<inputs>` block
    declares `AIDP_ARTIFACTS_ROOT` as a required orchestrator-provided
    var.
  - `.claude/rules/decision-surfacing.md` — references to
    `docs/current-plan.md` and `docs/research/<topic>.md` updated to
    `${RUN_DIR}/...`.
  - `scripts/specs/render-html.sh` — sources
    `scripts/lib/project-root.sh`, resolves `AIDP_ARTIFACTS_ROOT` via
    the boundary parser, and reads/writes
    `${AIDP_ARTIFACTS_ROOT}/specs/` (and `…/specs/_site/`) instead of
    the hardcoded `$REPO_ROOT/docs/specs`. Fails closed if the
    resolver fails.

## [0.17.0] - 2026-05-11

### Added

- **`AIDP_PROJECT_ROOT` / `AIDP_ARTIFACTS_ROOT` anchoring.** New boundary
  parser at `scripts/lib/project-root.sh` exposes
  `aidp_resolve_project_root` (canonicalizes `CLAUDE_PROJECT_DIR` →
  `$(pwd)` via `pwd -P`) and `aidp_resolve_artifacts_root` (returns
  `${root}/docs/aidp` for consumer projects; `${root}/docs` when the
  plugin's own `.claude-plugin/plugin.json` with `name=ai-dev-pipeline`
  is present). `/ship`, `/review`, `/refactor`, `/audit`, `/research`
  export both vars at Step 0; every helper script consumes them. Fixes
  the long-standing issue where running `/ship` from an external
  consuming repo silently wrote run artifacts into the plugin checkout
  because `harness_cd_repo_root` chdir's into the plugin for self-checks.
- `scripts/tests/test-project-root.sh` — boundary-parser contract tests
  (8 cases incl. plugin-name detection, consumer-vs-plugin classification,
  fail-closed on missing dirs). Registered in
  `scripts/validate-claude-config.sh`.

### Changed

- **Run artifact layout for consumer projects** moves from
  `docs/runs/<id>/` (cwd-relative) to
  `${AIDP_ARTIFACTS_ROOT}/runs/<id>/` (absolute). Pointer files
  (`latest`, `latest.txt`, `latest-green.txt`) move alongside; the
  workflow-state pointer (`.claude/workflow-state/active`) stays under
  `AIDP_PROJECT_ROOT`. Consumer projects now namespace plugin output
  under `docs/aidp/` instead of polluting the project's top-level
  `docs/`. The plugin's own development checkout keeps the legacy
  `docs/` layout. `RUN_DIR` is always absolute; `smoke-bootstrap.sh`
  rejects a relative or empty `RUN_DIR` fail-closed.
- Migrated to the new anchor: `mint-run-id.sh`, `prune-runs.sh`,
  `resolve-run.sh`, `run-verification-gates.sh`, `promote-latest-green.sh`,
  `coverage-precondition.sh`, `check-adrs.sh`, `check-workflow-artifacts.sh`,
  `check-report-quality.sh`, `smoke-bootstrap.sh`, and the
  `.claude/hooks/plan-gate.sh` + `_hook_lib.sh` hook helpers. No
  cwd-relative `docs/runs` or `docs/latest` paths remain in production
  code.
- Plugin-vs-consumer detection is hardened to require
  `"name":"ai-dev-pipeline"` in `plugin.json`, not just file presence,
  so consumers that happen to ship their own Claude plugins are
  classified correctly.
- `resolve-run.sh` `dir` subcommand now returns the absolute
  `${AIDP_ARTIFACTS_ROOT}/runs/<id>` path; previously returned bare
  `docs/runs/<id>`.

### Migration notes

- Consumers updating in place: artifacts previously written to
  `<your-project>/docs/runs/<id>/…` will now land in
  `<your-project>/docs/aidp/runs/<id>/…`. Pre-existing runs are not
  migrated; you can `mv docs/runs docs/aidp/runs && mv docs/latest{,.txt}
  docs/aidp/` if you want history continuity, or just let new runs
  populate the new location.
- Anyone scripting against `docs/runs` / `docs/latest` directly should
  read `AIDP_ARTIFACTS_ROOT` from the orchestrator instead.

## [0.16.2] - 2026-05-11

### Fixed

- All bare `scripts/<x>` and `docs/templates/<x>` references in
  `.claude/commands/*.md` and `.claude/agents/*.md` are now prefixed with
  `${CLAUDE_PLUGIN_ROOT}/`. Previously these paths resolved against the
  consuming project's CWD (where nothing exists), breaking `/ship`,
  `/review`, `/refactor`, `/audit`, and `/research` on a fresh install.
  Write-target paths (`${RUN_DIR}/...`, `docs/runs/...`, user project
  artifacts) are intentionally left unprefixed — they must land in the
  consuming repo. Agent files that already had the correct dual
  `repo-wins / ${CLAUDE_PLUGIN_ROOT} fallback` template-resolve pattern
  are left untouched. Backwards compatibility is explicitly not a goal
  for this fix; `${CLAUDE_PLUGIN_ROOT}` is set in both plugin-install and
  in-repo development contexts.
- `scripts/run-verification-gates.sh` previously hard-coded
  `bash .claude/hooks/type-check.sh`, `bash .claude/hooks/lint-on-edit.sh`,
  and `bash scripts/security-scan.sh` as CWD-relative invocations. On a
  zero-setup install these paths did not exist in the consuming project,
  causing every typecheck/lint/security gate to crash. Each invocation
  now routes through `harness_resolve_artifact`, which prefers a
  repo-local copy and falls back to `${CLAUDE_PLUGIN_ROOT}/` when the
  user has not vendored the script. End-to-end verified from a clean
  tmpdir: all six gates green, exit 0.

## [0.16.1] - 2026-05-10

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
