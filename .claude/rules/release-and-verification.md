# Release and Verification Rules

## Gate Policy
- Blocking: type errors, test failures, security findings at error severity.
- Advisory: warnings (tracked but non-blocking in v1).

## Verification Sequence
1. Type check / compile
2. Lint
3. Security scan (if configured)
4. Property-based tests
5. Contract tests
6. Full test suite

## Output Artifacts
- `docs/test-report.md`
- `docs/verify-report.md`
- `docs/review-report.md`

## Reuse Guidance
- Keep commands tool-agnostic and auto-detect available package manager/runtime.
- Expose project overrides through environment variables when needed.
