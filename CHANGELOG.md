# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.0] - 2026-05-14

### Added

- **`.claude/skills/reset/SKILL.md`** — functional protocol for clearing
  stale workflow state (`.claude/workflow-state/active` + per-run state
  file). Run artifacts under `docs/aidp/runs/` are preserved. Resolves
  the long-standing reference-without-implementation gap surfaced by the
  agent-native review.
- **Test phase in `/ship`.** `tester` agent is now dispatched as phase 5
  between Review and Verify, populating
  `${RUN_DIR}/test-results.json` so the verifier's `full_suite` cache
  has a producing source. Skip clause for docs-only runs.
  `workflow-gate.sh` verifier profile accepts either `test` or
  `review` completion for backward compatibility.
- **Queue-mode resume protocol in `/ship`.** After parsing
  `.pending-approval.json`, the orchestrator validates `plan_hash`,
  checks the time-box deadline, re-emits the gate's `AskUserQuestion`,
  branches on the verb, and single-uses the marker. Replaces the
  previous "parse and fall through" silence.
- **Plan-Gate Bypass docs in
  `.claude/rules/release-and-verification.md`.** `PLAN_GATE_BYPASS=1`
  and `PLAN_GATE_MODE=warn|off|block` are now documented next to the
  existing Workflow-Gate Bypass section, alongside the automatic
  pass-conditions.

### Fixed

- **`workflow-gate.sh` `[gate-bypass:…]` regex is anchored.** Comment
  claimed "cannot hide inside pasted content" but the `=~` match was
  unanchored, so any pasted code containing the token in the first 200
  characters silently bypassed the gate and forged the audit log. The
  regex now requires the token at the start of the prompt; new test
  case (`tests/scripts/test-workflow-gate-bypass.sh`) enforces
  mid-prompt rejection.
- **`scripts/check-boundary-violations.sh` actually detects
  violations.** `rg --glob` was being passed dir-prefixed patterns
  (`src/**/core/**`) that rg never matched because `--glob` operates
  on paths relative to the search root. Boundary check was a no-op
  whenever `rg` was available; now uses bare suffix patterns
  (`**/core/**`).
- **`workflow-gate.sh` audit-log JSON injection in the no-jq fallback.**
  The plain-printf fallback embedded `bypass_reason` and `agent_type`
  unescaped, allowing a crafted reason to forge audit records. Added a
  minimal `_jstr` escape (backslash, quote, newline, control chars)
  matching the `decisions-core.sh` pattern.
- **`plan-gate.sh` path resolution and glob anchoring.**
  `bash scripts/parse-run-id.sh` was CWD-relative and silently fell
  back to the artifacts root when cwd ≠ repo root; now resolved via
  `${BASH_SOURCE[0]}`. The case-pattern globs `*/docs/*` and
  `*/scripts/*` matched application code in those subdirectories
  (e.g. `src/scripts/db-migration.py` bypassed the plan gate); now
  match repo-relative paths so only top-level `docs/`, `scripts/`,
  `.claude/`, etc. bypass.
- **`session-start.sh` JSON escaping and missing-skill behavior.**
  Replaced the hand-rolled `escape_for_json` with `jq -Rs`; the bash
  fallback now covers the full C0 control range. Missing
  `SKILL_PATH` now exits non-zero with a stderr error instead of
  injecting the literal string `"Error reading using-pipeline skill"`
  as valid JSON context.
- **`run-verification-gates.sh` orphans background gate jobs on CI
  SIGTERM.** Added `_cleanup_background_gates` trap on
  `EXIT INT TERM` that kills `pid_typecheck`/`pid_lint`/`pid_security`.
- **`mint-run-id.sh` `ci_disambiguator` collided across GitHub Actions
  matrix jobs.** Every job in a matrix shares `$GITHUB_RUN_ID`, so
  `% 256` produced identical disambiguators → identical run IDs →
  `workflow-state-update.sh` (no flock) lost writes between jobs. Now
  hashes `GITHUB_RUN_ID:GITHUB_JOB:MATRIX_INDEX:GITHUB_RUN_ATTEMPT`
  through `shasum` (with `sha256sum`/`cksum` fallback).
- **Reviewer canonical STATUS shape silently disabled auto-approve.**
  The combined `blocking=0 advisory=3` pipe-field made
  `parse-status-line.sh` hand `policy_apply` a non-integer value
  (`"0 advisory=3"`), so the regex check `^[0-9]+$` failed and the
  release gate fell back to `prompt` on every clean review. The
  reviewer agent now emits `blocking=N` and `advisory=M` as separate
  pipe-fields; `parse-status-line.sh` recognizes `advisory=` as a
  known informational key.
- **Security gate is now advisory by default.** `cargo audit`,
  `pip-audit`, and `govulncheck` have no native severity threshold,
  so the previous blocking behavior over-blocked against the v1 Gate
  Policy that "warnings are tracked but non-blocking". Set
  `SECURITY_SCAN_REQUIRED=1` to restore blocking behavior.
- **`parse-approvals-policy.sh` time_box positivity.** Regex
  `^[0-9]+$` accepted `0` despite invariant I6 declaring positive
  integers. Now uses `^[1-9][0-9]*$`.
- **`prune-runs.sh` `RUN_RETENTION=0` no longer deletes all
  unreferenced runs.** Explicit reject branch with clear error
  message.
- **`scripts/coverage-precondition.sh`, `promote-latest-green.sh`,
  `validate-claude-config.sh`, `render-end-of-run.sh`, and one missed
  call site in `run-verification-gates.sh`** now source
  `scripts/lib/style.sh` and use the documented emitters
  (`style::step`, `style::ok`, `style::fail`, `style::rule`) instead
  of raw printf with hardcoded glyphs. Aligns with the output-style
  rule's "scripts MUST source it rather than re-implement banners".
- **`scripts/parse-run-id.sh` inline comment.** Stale
  `max 24 (with both Z and -hh disambiguator)` corrected to `max 26`
  (length guard was already correct).

### Removed

- **`setup` skill reference in
  `.claude/skills/using-pipeline/SKILL.md`.** Referenced as a callable
  skill but never had a `SKILL.md` file. Replaced with a one-line note
  that vendoring assets into a consumer repo for CI is a manual
  one-off (copy `scripts/`, `.claude/rules/`, `docs/templates/`), not
  a skill invocation.

## [0.19.1] - 2026-05-14

### Fixed

- **`PostToolUse:Edit` hook no longer fails on monorepos with a TUI-mode
  task runner.** `.claude/hooks/_hook_lib.sh` now exports a small block
  of widely-respected non-interactive conventions (`CI=1`, `NO_COLOR=1`,
  `NPM_CONFIG_FUND=false`, `NPM_CONFIG_AUDIT=false`) plus
  `TURBO_UI=false` as a belt-and-suspenders override. Each variable is
  only set when the caller has not pinned one (`${VAR:-…}`). Before this
  change, editing a TypeScript file in a turbo monorepo whose
  `turbo.json` hard-codes `"ui": "tui"` produced two spurious
  `PostToolUse:Edit hook error — Failed with non-blocking status code: •
  turbo 2.9.12` lines on every edit, because turbo printed only its
  banner before exiting non-zero in the absence of a TTY. The fix is
  tool-agnostic: any child process that honors `CI` (turbo, pnpm, npm,
  jest, vitest, husky, lint-staged, …) now picks stream output without
  the hook naming the tool.

## [0.19.0] - 2026-05-14

### Added

- **In-band workflow-gate bypass token.** `.claude/hooks/workflow-gate.sh`
  now honors a literal `[gate-bypass: <reason>]` token in the first 200
  characters of an `Agent` tool prompt, allowing per-call opt-out when the
  user has approved out-of-band or no `/ship` run is active. Before this
  change, a stale `.claude/workflow-state/active` from an abandoned run
  blocked every `implementer`/`reviewer`/`tester`/`verifier` invocation,
  silently driving fallback to `general-purpose` and dropping the FC/IS
  specialization. Token parsing is anchored, requires a non-empty reason,
  and fails closed on any malformed input. Every honored bypass appends
  one JSON record (`{timestamp, agent_type, reason, run_id}`) to
  `${RUN_DIR:-/tmp}/gate-bypass.log` for audit. `WORKFLOW_GATES_SKIP=1`
  (session-wide) and `/reset` (stale-state clear) remain alternatives.
  The blocked-failure message now names all three bypass paths so the
  mechanism is discoverable at the point of failure instead of buried in
  rules docs. Documented in
  `.claude/rules/release-and-verification.md` §Workflow-Gate Bypass; the
  `implementer` agent gained a one-line note so it ignores the token for
  task semantics. Tests:
  `tests/scripts/test-workflow-gate-bypass.sh` covers valid token,
  missing token (with discoverable failure message), malformed token
  (empty reason → fail closed), and token past the 200-char anchor →
  ignored. The existing `test-workflow-gate-lean-order.sh` still passes.

## [0.18.2] - 2026-05-14

### Fixed

- **Harden subagents against truncation on big tasks.** Three layered
  constraints address truncated final messages and mid-run context
  exhaustion observed on multi-file implementer dispatches. (1) New
  `<final-message>` block on all 7 agents (`auditor`, `implementer`,
  `planner`, `researcher`, `reviewer`, `tester`, `verifier`) caps the
  final assistant reply to ≤400 chars before the STATUS line and forbids
  diffs, file dumps, log spew, and long enumerations in chat — substance
  routes to the on-disk deliverable. (2) New `<progressive-writes>`
  block on `implementer` instructs it to write the `## Implementation`
  section incrementally (stub at start, edit-append per landed unit,
  finalize Summary last) so partial progress survives mid-run
  truncation; `GATE-no-touch` reworded to permit incremental updates
  to the implementer's own trailing section while keeping
  planner-authored sections byte-protected. (3) New
  `<context-discipline>` block on `implementer` enforces Grep-before-Read
  with `offset`/`limit`, no in-session re-reads, Edit over Write, and
  TodoWrite-driven progress instead of in-chat self-summaries; bumps
  `maxTurns` 40 → 60 (the bump only helps with the discipline).

## [0.18.1] - 2026-05-13

### Fixed

- **Route hook block/error messages to stderr so Claude Code surfaces them.**
  PreToolUse hooks that exit non-zero must emit their diagnostic on stderr
  for the harness to display it to the agent; previously several hooks
  echoed the reason to stdout, producing the unhelpful generic
  `PreToolUse:Agent hook error … No stderr output` message and hiding the
  actual cause. `.claude/hooks/workflow-gate.sh` (4 block sites:
  implementer/reviewer/tester/verifier), `.claude/hooks/protect-files.sh`
  (protected-file block), `.claude/hooks/format-on-stop.sh`,
  `.claude/hooks/lint-on-edit.sh`, and `.claude/hooks/type-check.sh`
  (advisory `ERROR` lines preceding `exit 1`) now redirect their messages
  to stderr. Behavior of `plan-gate.sh` and `_hook_lib.sh::run_advisory`
  was already correct and is unchanged. Informational `skipped (...)`
  messages paired with `exit 0` are intentionally left on stdout.

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
