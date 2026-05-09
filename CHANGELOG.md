# Changelog

All notable changes to `ai-dev-pipeline` are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-05-09

### **BREAKING**

- **Removed `adaptive` mode from `/ship`.** The legacy `adaptive` mode token is
  no longer recognized. `/ship adaptive` is now a hard error: the orchestrator
  emits `↷ unrecognized mode "adaptive"; valid modes are: <empty> | "strict" | "fast" | "research <topic>"`
  and exits non-zero. No alias, no banner, no silent default. Migration: drop
  the explicit `adaptive` argument (the previous default), or invoke `/ship`
  with no arguments — `fast` is the new default and reproduces the prior
  risk-conditional plan-gate behavior. Scripts and CI pipelines that pinned
  `/ship adaptive` must be updated. See `.claude/commands/ship.md` ("Mode
  argument") for the new closed grammar.

### Added

- **`mode=fast` is the new default for `/ship`.** Identical risk-conditional
  plan gate as the prior `adaptive` mode, with a fast-low short-circuit
  (`mode=fast` AND `risk=low` AND `change_class ∈ {trivial, config_only}`):
  research is skipped, the standalone review is folded into
  verify-report's `## Advisory Review` section, and a single approval gate
  fires at release.
- **`change_class=config_only` sibling tier.** Joins `trivial` and `standard`.
  The `/ship` orchestrator authoritatively classifies the change from
  `git diff --name-only` against the merge-base; only Markdown / YAML / JSON /
  `.claude/{agents,skills,rules,hooks}/**` paths qualify. Any file outside the
  allowlist (mixed diff) forces `change_class=standard` (fail-closed). Under
  `config_only` the orchestrator skips the TDD pre-phase + tester invocation
  and skips the standalone reviewer invocation; verify narrows to
  `validate-claude-config.sh` plus configured lint via the `VERIFY_*_CMD=":"`
  empty-command path.
- **Auto-promotion `fast → strict`.** When `mode=fast` and the planner reports
  `risk=medium` or `risk=high`, the orchestrator prints
  `⏵ promoting fast → strict (risk=<tier>)` exactly once (one-shot,
  idempotent) and continues in strict mode. The run does NOT abort.
- **Risk-scaled plan template.** `docs/templates/current-plan-template.md`
  now marks Non-Goals, Out-of-Scope, Boundary Parsers, FC/IS Classification,
  Invariants, and Failure Modes as **Optional (omit for `risk=low`)** via
  HTML comments. Risk=low plans target ≤30 lines.
- **`change-class:` field** in plan front-matter / Risk Profile, alongside the
  existing `change-type:` field. Planner STATUS line now includes a
  `change-class=<trivial|config_only|standard>` token between `risk=` and the
  summary segment.
- **Verify-report `## Advisory Review` section** for folded reviewer findings
  under the fast-low short-circuit.

### Changed

- `scripts/check-workflow-artifacts.sh` `parse_change_type` accepts both
  `change-type:` and `change-class:` field names, and the `config_only` token.
  Under `config_only`, both the `docs/specs/*.md` requirement and the
  `docs/review-report.md` requirement are skipped (folded into verify-report).
- `.claude/rules/release-and-verification.md` Human Approval Policy now keys
  the release auto-approval carve-out on `mode=fast` instead of `adaptive`.
  The Canonical Gate Runner section endorses `config_only` verify narrowing.

### Migration notes

- Pre-existing `/ship adaptive` invocations: drop the argument (`/ship`) or
  switch to `/ship strict` if you relied on unconditional plan approval.
- Plans that declared `change-type: config` continue to work; `config_only` is
  a stricter sibling that additionally folds review-report into verify-report.

## [0.8.0] - 2026-04

Prior release; see git history.
