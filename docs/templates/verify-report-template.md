# Verify Report Template

## Context
- Risk tier: `low` | `medium` | `high`
- Change type:
- Reviewer:

## Gate Results
1. Type/compile:
2. Lint:
3. Security:
4. Property tests:
5. Contract tests:
6. Full suite:

## Retry Envelope
- Retry count:
- Final exit codes per gate:
- Hint file: `docs/.verify-retry.json`

## Decision
- [ ] Go
- [ ] No-Go

## Finding Classification
- Blocking:
- Advisory:

## Human Approval Checkpoints
<!--
Convention: each numbered line must be filled. For risk=low changes, the three
approval slots may be filled with `N/A — <rationale>` (for example
`N/A — risk=low`) and the Evidence link should point at `docs/current-plan.md`.
A bare `N/A` or `na` without the dash + rationale is rejected by
scripts/check-report-quality.sh. For risk=medium or risk=high, all three slots
require concrete approver/date/evidence values.
-->
1. Plan approved: <!-- e.g. approved | N/A — risk=low -->
   - Approver:
   - Date:
   - Evidence link:
2. Elevated-risk implementation approved (required for `medium` and `high` risk): <!-- e.g. approved | N/A — risk=low -->
   - Approver:
   - Date:
   - Evidence link:
3. Release approved: <!-- e.g. approved | N/A — risk=low -->
   - Approver:
   - Date:
   - Evidence link:

## Evidence
- Official sources:
  - <!-- e.g. .claude/rules/release-and-verification.md -->
  - <!-- e.g. https://example.com/official-doc -->
- External sources (if needed, max 2):
  - <!-- omit if not needed -->
<!--
Canonical `Official sources:` form is the sub-bullet form shown above.
An inline value on the same line is also accepted by
scripts/check-report-quality.sh, but sub-bullets are preferred.
-->

## Residual Risk and Follow-ups
