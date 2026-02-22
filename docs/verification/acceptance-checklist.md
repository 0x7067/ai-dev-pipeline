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
- [ ] Blocking vs advisory policy is documented.
- [ ] Test strategy includes property-based and contract tests.

## Reuse
- [ ] Scripts are stack-agnostic and command-detecting.
- [ ] No hardcoded project-specific runtime assumptions.
