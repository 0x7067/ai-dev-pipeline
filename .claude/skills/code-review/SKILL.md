---
name: code-review
description: Use when the user asks to review, check, look at, audit, or assess code — phrases like "review this", "is this OK", "does this look right", "check my changes" — and proactively after any non-trivial implementation, before reporting code as done. Severity-first FC/IS, security, and correctness lenses. Produces `docs/review-report.md`. Do not invoke for project-wide audits (use `/audit`) or pre-implementation planning.
---

# Code Review

## Review Workflow

1. Read all changed files to understand the full scope.
2. Classify each changed file as `core`, `shell`, or `boundary`.
3. Apply each review lens (below) in order.
4. Record findings by severity: blocking → warning → advisory.
5. If no findings, state residual risk explicitly — never leave a silent pass.
6. Write output to `${RUN_DIR}/review-report.md` (the orchestrator sets `RUN_DIR` at /ship step 0; falls back to `docs/review-report.md` only when invoked outside a /ship-managed run).

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

### 6. Pragmatic Checklist (single-pass — folded in 2026-05)

Run this checklist inline as part of the same pass on changes classified `medium` or `high` risk. For `low` risk, skip — the lenses 1–5 above are sufficient. Findings here are **advisory** unless they overlap an existing rule in `.claude/rules/` (escalate to `warning` and cite the rule).

For each finding, cite `file:line` and quote up to three lines of evidence.

#### Change-amenability
- [ ] **Tracer bullet vs. prototype declared.** For new features, does the plan or PR description say which it is? Tracer bullets stay in the codebase; prototypes are thrown away. *(Tips 20, 21)*
- [ ] **Reversibility.** Does this change lock in a vendor, a schema, or a protocol that will be expensive to undo? If yes, is that called out? *(Tip 18)*
- [ ] **Step size.** Does the diff do one thing, or several? Multi-purpose diffs hide regressions. *(Tip 42)*
- [ ] **No fortune-telling.** Are there abstractions, hooks, or config knobs added "just in case" with no current caller? *(Tip 43)*

#### Decoupling
- [ ] **Train wrecks.** Any chain like `a.b.c.d` across module boundaries? Flag and recommend a domain method. *(Tips 44, 46)*
- [ ] **Tell, don't ask.** Any code that reads object state, decides, and writes back? *(Tip 45)*
- [ ] **Inheritance for reuse.** Is subclassing used to share code rather than to express polymorphism? Recommend composition. *(Tips 51-53)*

#### State and data
- [ ] **Hoarded state.** Any object accumulating state across calls when a value would do? *(Tip 50 — already in FC/IS; surface as warning if violated.)*
- [ ] **Acted globally.** Did the change touch global, static, or singleton mutables? *(Tips 47, 48 — escalate to warning, reference `decoupling-and-configuration.md`.)*
- [ ] **Data shape.** Does the code transform plain data through pipelines, or operate on heavy objects with hidden state? *(Tip 49)*

#### Correctness and contracts
- [ ] **Stated invariants asserted.** If the code or comment says "this can never be null/empty/negative", is there an assertion? *(Tip 39 — escalate to warning, reference `assertions-and-invariants.md`.)*
- [ ] **Contracts on new functions.** Do new core functions document or test pre/postconditions? *(Tip 37)*
- [ ] **Programming by coincidence.** Any code that "works" but the author cannot explain why? Look for unmotivated `try/catch`, unexplained sleeps, copy-pasted blocks. *(Tip 62)*
- [ ] **Failing test before fix.** For bug-fix PRs, is there a test that fails on the old code and passes on the new? *(Tip 31 — escalate to warning if missing.)*
- [ ] **Find bugs once.** For each bug fixed, is there a regression test? *(Tip 94)*

#### Resource ownership
- [ ] **Balanced resources.** Every `open`/`acquire`/`begin` has a matching close on every exit path including exceptions. *(Tip 40 — escalate to warning, reference `assertions-and-invariants.md`.)*

#### Concurrency (if touched)
- [ ] **Shared mutable state across threads or tasks.** *(Tip 57 — escalate to warning if present in core.)*
- [ ] **Random failures.** Any new flakiness or order-dependent tests? Likely a concurrency issue, not "just retry". *(Tip 58)*

#### Tests
- [ ] **Test as first user.** Is the public API ergonomic in the test? Awkward tests indicate awkward API. *(Tip 67)*
- [ ] **State coverage, not line coverage.** Are the meaningful states and transitions tested, or just lines hit? *(Tip 93)*
- [ ] **Saboteurs.** Has at least one mutation been verified to make a test fail? Tests that pass against any code are dead. *(Tip 92)*

#### Documentation and naming
- [ ] **Names by domain intent.** *(Tip 74 — already in `code-style.md`. Surface only if violated.)*
- [ ] **Docstrings or ADRs alongside code.** Non-obvious decisions captured in code or in `docs/`. *(Tip 13)*
- [ ] **Broken windows.** Commented-out code, `TODO` without issue link, dead branches. *(Tip 5)*

Append surfaced findings to the `## Advisory Findings (Model)` section of the report. If nothing surfaces, add a single line under that section: `Pragmatic checklist: clean. Residual concern: <one sentence or "none">.`

## Output

- `${RUN_DIR}/review-report.md` (per-run artifact under `docs/runs/<id>/`; resolved via `RUN_DIR` env or `scripts/resolve-run.sh`).
- Findings ordered by severity, grouped by lens.
- Evidence summary with file:line references.
- Residual risk statement at the end.
