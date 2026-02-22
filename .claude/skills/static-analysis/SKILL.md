---
name: static-analysis
description: Run deterministic verification checks and produce a blocking/advisory summary. Use when verifying code quality gates, running lint and type checks, or producing a go/no-go decision.
---

# Static Analysis

## Checks
1. Type check or compile
2. Lint
3. Security scan (if available)
4. Test status checks

## Gate Policy
- Blocking: errors/failures
- Advisory: warnings

## Output
- `docs/verify-report.md`
- Include command list, exit statuses, and blocking decision.
