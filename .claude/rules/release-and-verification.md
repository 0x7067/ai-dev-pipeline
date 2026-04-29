# Release and Verification Rules

## Gate Policy
- Blocking: type errors, test failures, security findings at error severity.
- Advisory: warnings (tracked but non-blocking in v1).

## Gate Authority
- Only CI-tier gates are authoritative. Pre-commit hooks and local runs are convenience layers and may be bypassed (`--no-verify`).
- A change is "verified" only when `scripts/run-verification-gates.sh` has exited 0 in CI on the merge commit.
- Source: appxlab, "Quality Gates for AI-Generated Code: CI/CD Pipeline Guide" (2026-04-06).

## Verification Signals
- Blocking signals must be tool-derived: compile/typecheck, lint, test, SAST.
- Model self-critique is advisory and never blocking. The `review` skill produces advisory findings; the `verify` skill produces the go/no-go decision from tool exit codes.
- Source: AgentPatterns, "Verification-Centric Development for AI-Generated Code"; Sonar, "The future is AC/DC" (2026-03-02).

## Risk Tiers
- `low`: routine change with bounded blast radius.
- `medium`: cross-module behavior change or non-trivial refactor.
- `high`: security-sensitive, data-integrity, auth/authz, or release-critical change.

## Human Approval Policy
- Plan gate: required before implementation starts.
- Elevated-risk implementation gate: required for `medium` and `high` risk tiers before code changes are finalized.
- Release gate: required before go/no-go is marked `Go`.

## Verification Sequence
1. Type check / compile
2. Lint
3. Security scan (if configured)
4. Property-based tests
5. Contract tests
6. Full test suite

## Canonical Gate Runner
- Use `bash scripts/run-verification-gates.sh` as the single source of truth for gate execution order.
- Allow overrides via environment variables for project-specific commands.
- Optional bounded retry: set `MAX_VERIFY_RETRIES` (default `0`) to enable a `verify → fix → verify` envelope. On gate failure the runner writes `{gate, exit_code, attempt}` to `VERIFY_RETRY_HINT_FILE` (default `docs/.verify-retry.json`) for the `verify` skill to consume on the next pass.

## Evidence Quality
- Every verification or review claim must include evidence.
- Sources must prioritize official documentation.
- Maximum two external non-official sources when needed.
- Numeric impact claims without evidence are invalid and treated as advisory at minimum.

## Output Artifacts
- `docs/test-report.md`
- `docs/verify-report.md`
- `docs/review-report.md`
- `docs/refactor-report.md`
- `docs/audit-report.md`
- `docs/templates/workflow-assessment-report-template.md`

## Reuse Guidance
- Keep commands tool-agnostic and auto-detect available package manager/runtime.
- Expose project overrides through environment variables when needed.
- Keep templates parameterized so they can be copied across repositories.
