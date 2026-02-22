# Acceptance Checklist

## Wiring
- [ ] `.claude/settings.json` parses with `jq`.
- [ ] All commands reference existing agents.
- [ ] All agents reference existing skills.
- [ ] `CLAUDE.md` rule references resolve.

## Architecture
- [ ] FC/IS layering rules are documented.
- [ ] Parse-at-boundary rule is documented and strict.
- [ ] Core nondeterminism is disallowed by policy.

## Verification
- [ ] Validation scripts run cleanly.
- [ ] `bash scripts/smoke-bootstrap.sh` passes with `SUMMARY|...|failed=0`.
- [ ] `bash scripts/check-report-quality.sh` passes (or intentionally skipped for empty bootstrap artifacts).
- [ ] `bash scripts/check-workflow-artifacts.sh` passes (or intentionally skipped for empty bootstrap artifacts).
- [ ] Blocking vs advisory policy is documented.
- [ ] Test strategy includes property-based and contract tests.
- [ ] Verification requires evidence summary and source citations.
- [ ] Unsourced numeric claims are rejected by policy.
- [ ] Active workflow verify step runs strict gates with `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1`.

## Human Oversight
- [ ] Plan approval checkpoint is documented.
- [ ] High-risk implementation requires explicit approval.
- [ ] Release approval checkpoint is documented.

## Reuse and Assessment
- [ ] Scripts are stack-agnostic and command-detecting.
- [ ] No hardcoded project-specific runtime assumptions.
- [ ] Workflow assessment prompt template exists.
- [ ] Workflow assessment rubric template exists.
- [ ] Workflow assessment report template exists.
