---
name: code-review
description: Use when the user asks to review, check, look at, audit, or assess code — phrases like "review this", "is this OK", "does this look right", "check my changes" — and proactively after any non-trivial implementation, before reporting code as done. Severity-first FC/IS, security, and correctness lenses.
---

# Code Review

## Review Workflow

1. Read all changed files to understand the full scope.
2. Classify each changed file as `core`, `shell`, or `boundary`.
3. Apply each review lens (below) in order.
4. Record findings by severity: blocking → warning → advisory.
5. If no findings, state residual risk explicitly — never leave a silent pass.
6. Write output to `docs/review-report.md`.

## Review Lenses

### 1. Architecture Boundaries (core/shell/boundary)

Check that layer rules are respected:

```
# ❌ BLOCKING — core imports shell module
# src/core/pricing.py
from src.shell.database import get_discounts   # side-effect dependency in core

# ✅ CORRECT — core receives data as parameter
def apply_discounts(price: Decimal, discounts: list[Discount]) -> Decimal:
    ...
```

- Core must not import shell or perform I/O.
- Shell must not contain business decisions beyond routing.
- Boundary must parse before forwarding to core.

### 2. Boundary Parsing Compliance

Check every ingress point (HTTP, CLI, env, queue, file read):

```
# ❌ BLOCKING — raw request body passed to core
result = process_order(request.json)

# ✅ CORRECT — parsed at boundary first
order = parse_order(request.json)   # raises on invalid input
result = process_order(order)
```

- Verify parsers return typed domain values or structured errors.
- Check that core functions never accept `dict`, `Any`, or raw strings from external sources.

### 3. Security and Secrets Hygiene

- No secrets, API keys, tokens, or private keys in committed code.
- Sensitive files (`.env*`, `*.pem`, `*.key`) not added to version control.
- No logging of sensitive payloads (request bodies with auth tokens, PII).
- External input treated as untrusted until parsed.
- Fail closed on parser/authn/authz errors (deny by default).

### 4. Correctness and Edge Cases

- Off-by-one errors in loops and ranges.
- Null/undefined handling at boundaries.
- Race conditions in concurrent code.
- Error paths that swallow exceptions silently.
- Division by zero, empty collections, integer overflow.

### 5. Test Adequacy

- Core invariants covered by property-based tests.
- Boundary parsers covered by contract tests (accept/reject).
- New code paths have corresponding test cases.
- Regression tests for previously known failures.

## Severity Classification

| Severity | Meaning | Action |
|----------|---------|--------|
| **Blocking** | Must fix before merge. Architectural violation, security issue, or broken invariant. | Stops the pipeline. |
| **Warning** | Should fix. Correctness risk, missing test, or code smell. | Tracked, non-blocking in v1. |
| **Advisory** | Consider fixing. Style, naming, minor improvement. | Informational only. |

## Finding Format

Each finding must include:

```
### [BLOCKING] Raw API response used in core pricing logic

**File:** src/core/pricing.py:42
**Lens:** Boundary parsing compliance
**Issue:** `calculate_total()` accepts `raw_response: dict` directly from
the HTTP client without parsing through a boundary type.
**Recommendation:** Add `parse_price_response()` at the shell layer and
pass the parsed `PriceQuote` domain type to core.
```

## Blocking Conditions (auto-reject)

- Raw ingress data used in core/domain logic.
- Missing parser at a documented boundary.
- Untested critical invariant.
- Committed secrets or credentials.
- Core function performing I/O or reading ambient state.

## Output

- `docs/review-report.md`
- Findings ordered by severity, grouped by lens.
- Evidence summary with file:line references.
- Residual risk statement at the end.
