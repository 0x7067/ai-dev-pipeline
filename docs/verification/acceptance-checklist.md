# Acceptance Checklist (medium / high risk runs)

This checklist documents the human-approval gates required by
`.claude/rules/release-and-verification.md` ("Human Approval Policy") and
the verification sequence asserted by `scripts/run-verification-gates.sh`
on every change.

`scripts/smoke-bootstrap.sh` enforces the presence of this file as part
of `required_bootstrap_files` so a freshly-initialized pipeline cannot
silently lose the canonical acceptance contract.

## Risk-Tier Trigger

A change qualifies for this checklist when the planner's `Risk Profile`
classifies it as `medium` or `high` (see `release-and-verification.md`
"Risk Tiers"). Low-risk changes follow the same flow but the
elevated-risk implementation gate degrades to `N/A — <rationale>`
(enforced by `scripts/check-report-quality.sh`).

## Human Approval Gates (in pipeline order)

1. **Plan approval gate** — required before any source modification.
   - Approver records `Plan approved`, `Approver`, `Date`, and an
     `Evidence link` in `${RUN_DIR}/verify-report.md` under
     `## Human Approval Checkpoints`.
   - Plan must be readable (the `/ship` plan-preview helper renders the
     four canonical sections; absence of the helper output is not a
     gate failure but the plan file must still parse).

2. **Elevated-risk implementation gate** — required for `medium` and
   `high`. Runs after `implementer` + `reviewer` and BEFORE final
   verification.
   - Approver attests that the code change matches the approved plan
     and that the reviewer's blocking findings (if any) have been
     resolved.
   - For `low` risk this gate is recorded as
     `N/A — <one-line rationale>`.

3. **Release approval gate** — required before `verify-report.md`'s
   `Decision` field is marked `Go`.
   - Verifier must have produced a `go` STATUS, the smoke gate
     (`scripts/smoke-bootstrap.sh`) must have exited 0, and all
     blocking gate exit codes must be zero.

## Tool-Derived Verification (blocking)

Run through `scripts/run-verification-gates.sh` in order; only this
runner is authoritative (per "Gate Authority"):

1. Type check / compile
2. Lint
3. Security scan (if configured)
4. Property-based tests
5. Contract tests
6. Full test suite

Any non-zero exit code in 1–6 blocks the release approval gate. Model
self-critique findings (from `reviewer`) are advisory and never block
on their own — only the verifier's tool-derived signals do.

## Evidence Quality Requirements

Per `release-and-verification.md` "Evidence Quality":

- Every blocking claim must cite a tool exit code or an official
  source.
- External non-official sources are limited to a maximum of two per
  report.
- Numeric impact claims without evidence are advisory at best.

## Smoke Gate

The final smoke gate
(`REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1
bash scripts/smoke-bootstrap.sh`) must exit 0 before release approval
is requested. This file's presence is part of that gate's
`required_bootstrap_files` check.

## References

- `.claude/rules/release-and-verification.md` — canonical policy.
- `scripts/run-verification-gates.sh` — gate runner.
- `scripts/smoke-bootstrap.sh` — bootstrap completeness check.
- `scripts/check-report-quality.sh` — approval-field validator.
- `docs/templates/verify-report-template.md` — report shape consumed
  by the validator.
