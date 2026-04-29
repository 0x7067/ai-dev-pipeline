---
name: static-analysis
description: Use when the user asks to verify, ship, release, merge, or finalize code — phrases like "is this ready to ship", "verify this", "ready to merge", "run the gates", "is this done" — and after implementation to produce a go/no-go decision via type checks, lint, security scan, and the canonical gate runner. Produces `docs/verify-report.md`. Requires the implementation phase to be complete; do not invoke standalone for ad-hoc lint or type-check runs.
---

# Static Analysis

## Check Sequence

Run checks in this order. Stop and report on first blocking failure.

### 1. Type Check / Compile

Detect the project's language and run the appropriate checker:

| Language | Command |
|----------|---------|
| TypeScript | `npx tsc --noEmit` |
| Python (typed) | `mypy .` or `pyright` |
| Rust | `cargo check` |
| Go | `go vet ./...` |
| Java/Kotlin | `./gradlew compileJava` or `mvn compile` |

### 2. Lint

| Language | Command |
|----------|---------|
| TypeScript/JS | `npx eslint .` |
| Python | `ruff check .` or `flake8` |
| Rust | `cargo clippy` |
| Go | `golangci-lint run` |
| Shell | `shellcheck scripts/*.sh` |

### 3. Security Scan (if available)

| Tool | Command |
|------|---------|
| npm audit | `npm audit --audit-level=high` |
| pip-audit | `pip-audit` |
| trivy | `trivy fs .` |
| semgrep | `semgrep --config=auto .` |
| cargo-audit | `cargo audit` |

### 4. Property-Based Tests

Run property-based tests if configured (project-specific script).

### 5. Contract Tests

Run boundary parser contract tests if configured (project-specific script).

### 6. Full Test Suite

Detect and run the project's test runner:

| Runner | Command |
|--------|---------|
| pytest | `pytest --tb=short -q` |
| jest/vitest | `npx jest` or `npx vitest run` |
| cargo test | `cargo test` |
| go test | `go test ./...` |
| bun test | `bun test` |

## Tool Detection

Before running any command, verify it exists:

```bash
# Auto-detect package manager
if command -v bun &>/dev/null; then PM="bun"
elif command -v pnpm &>/dev/null; then PM="pnpm"
elif command -v yarn &>/dev/null; then PM="yarn"
elif command -v npm &>/dev/null; then PM="npm"
fi

# Auto-detect test runner
if [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then RUNNER="pytest"
elif [ -f "jest.config.js" ] || [ -f "jest.config.ts" ]; then RUNNER="jest"
elif [ -f "vitest.config.ts" ]; then RUNNER="vitest"
elif [ -f "Cargo.toml" ]; then RUNNER="cargo test"
fi
```

If a tool is not available, record it as `SKIPPED` (not as a failure).

## Gate Policy

| Exit code | Category | Action |
|-----------|----------|--------|
| Non-zero from type check | **Blocking** | Fail the gate. Must fix. |
| Non-zero from lint (errors) | **Blocking** | Fail the gate. |
| Lint warnings only | **Advisory** | Log and continue. |
| Security finding (high/critical) | **Blocking** | Fail the gate. |
| Security finding (low/medium) | **Advisory** | Log and continue. |
| Test failure | **Blocking** | Fail the gate. |
| Tool not found | **Skipped** | Log as skipped, not failure. |

## Output Format

Write to `docs/verify-report.md`:

```markdown
# Verification Report

**Date:** YYYY-MM-DD
**Risk Tier:** low | medium | high
**Decision:** GO | NO-GO

## Check Results

| # | Check | Command | Exit | Status |
|---|-------|---------|------|--------|
| 1 | Type check | `npx tsc --noEmit` | 0 | PASS |
| 2 | Lint | `ruff check .` | 1 | BLOCKING |
| 3 | Security | — | — | SKIPPED |
| 4 | Property tests | `npm run test:property` | 0 | PASS |
| 5 | Contract tests | `npm run test:contract` | 0 | PASS |
| 6 | Full suite | `pytest -q` | 0 | PASS |

## Blocking Findings

### Lint: 2 errors in src/core/pricing.py
- Line 42: unused import `os` (F401)
- Line 88: undefined name `calculate` (F821)

## Advisory Findings

(warnings logged here)

## Decision

NO-GO — 1 blocking finding remains.
```

## Anti-Patterns

```
# ❌ WRONG — treating missing tool as failure
$ mypy .
command not found: mypy
→ Gate result: FAIL               # incorrect — tool not configured

# ✅ CORRECT — record as skipped
$ mypy .
command not found: mypy
→ Gate result: SKIPPED (mypy not installed)

# ❌ WRONG — running checks out of order
Run tests first, then lint, then type check
→ Wastes time if type errors exist

# ✅ CORRECT — cheapest/fastest checks first
Type check → Lint → Security → Tests
→ Fails fast on cheapest check
```
