---
name: pragmatic-review-checklist
description: "Standalone-only reference skill. Curated review checklist drawn from The Pragmatic Programmer (20th Ed.) tips that are not enforceable by compiler or linter. Reviewer agent / `/review` no longer invokes this as a second pass — the medium/high-risk content was folded into `code-review` (single-pass) on 2026-05. Use this skill only when the user explicitly asks for a manual pragmatic-only review or a deep-dive on an existing diff."
---

# Pragmatic Review Checklist (standalone-only)

Advisory pass over a diff using behavior-changing tips from *The Pragmatic Programmer* (20th Anniversary Ed.) that are not already enforced by `.claude/rules/*` or by static analysis.

> **Note (2026-05):** the reviewer agent and `/review` command no longer invoke this skill as a second pass. The same checklist content now runs **inline** as lens 6 of the `code-review` skill on `medium`/`high`-risk changes, so each diff is reviewed in a single pass. This file remains for explicit standalone use (e.g. user asks for a "pragmatic-only review" outside a /ship run).

This skill produces an **advisory** section appended to `${RUN_DIR}/review-report.md` (the orchestrator sets `RUN_DIR` at /ship step 0; fail closed if `RUN_DIR` is unset — no top-level `docs/` fallback). Per `release-and-verification.md`, model self-critique never blocks. The blocking decision belongs to the gate runner.

## When to invoke
- Manually invoked when the user asks for a "pragmatic review" or "deep-dive checklist pass" outside the standard pipeline.
- NOT auto-invoked by `/review` or the reviewer agent — see note above.
- Skipped for trivial changes (typo, comment, single-line config) — the standard review is enough.

## Procedure
For each changed file, walk the checklist below in order. Group findings by section. For each finding, cite `file:line` and quote up to three lines of evidence. Severity is always `advisory` unless the finding overlaps a rule already in `.claude/rules/`, in which case escalate to `warning` and reference the rule.

## Checklist

### Change-amenability
- [ ] **Tracer bullet vs. prototype declared.** For new features, does the plan or PR description say which it is? Tracer bullets stay in the codebase; prototypes are thrown away. Code that is "kind of both" is the problem. *(Tips 20, 21)*
- [ ] **Reversibility.** Does this change lock in a vendor, a schema, or a protocol that will be expensive to undo? If yes, is that called out? *(Tip 18)*
- [ ] **Step size.** Does the diff do one thing, or several? Multi-purpose diffs hide regressions. *(Tip 42)*
- [ ] **No fortune-telling.** Are there abstractions, hooks, or config knobs added "just in case" with no current caller? *(Tip 43)*

### Decoupling
- [ ] **Train wrecks.** Any chain like `a.b.c.d` across module boundaries? Flag and recommend a domain method. *(Tips 44, 46)*
- [ ] **Tell, don't ask.** Any code that reads object state, decides, and writes back? *(Tip 45)*
- [ ] **Inheritance for reuse.** Is subclassing used to share code rather than to express polymorphism? Recommend composition. *(Tips 51-53)*

### State and data
- [ ] **Hoarded state.** Any object accumulating state across calls when a value would do? *(Tip 50 — already in FC/IS; surface as warning if violated.)*
- [ ] **Acted globally.** Did the change touch global, static, or singleton mutables? *(Tips 47, 48 — escalate to warning, reference `decoupling-and-configuration.md`.)*
- [ ] **Data shape.** Does the code transform plain data through pipelines, or operate on heavy objects with hidden state? *(Tip 49)*

### Correctness and contracts
- [ ] **Stated invariants asserted.** If the code or comment says "this can never be null/empty/negative", is there an assertion? *(Tip 39 — escalate to warning, reference `assertions-and-invariants.md`.)*
- [ ] **Contracts on new functions.** Do new core functions document or test pre/postconditions? *(Tip 37)*
- [ ] **Programming by coincidence.** Any code that "works" but the author cannot explain why? Look for unmotivated `try/catch`, unexplained sleeps, copy-pasted blocks. *(Tip 62)*
- [ ] **Failing test before fix.** For bug-fix PRs, is there a test that fails on the old code and passes on the new? *(Tip 31 — escalate to warning if missing.)*
- [ ] **Find bugs once.** For each bug fixed, is there a regression test? *(Tip 94)*

### Resource ownership
- [ ] **Balanced resources.** Every `open`/`acquire`/`begin` has a matching close on every exit path including exceptions. *(Tip 40 — escalate to warning, reference `assertions-and-invariants.md`.)*

### Concurrency (if touched)
- [ ] **Shared mutable state across threads or tasks.** *(Tip 57 — escalate to warning if present in core.)*
- [ ] **Random failures.** Any new flakiness or order-dependent tests? Likely a concurrency issue, not "just retry". *(Tip 58)*

### Tests
- [ ] **Test as first user.** Is the public API ergonomic in the test? Awkward tests indicate awkward API. *(Tip 67)*
- [ ] **State coverage, not line coverage.** Are the meaningful states and transitions tested, or just lines hit? *(Tip 93)*
- [ ] **Saboteurs.** Has at least one mutation been verified to make a test fail? Tests that pass against any code are dead. *(Tip 92)*

### Documentation and naming
- [ ] **Names by domain intent.** *(Tip 74 — already in `code-style.md`. Surface only if violated.)*
- [ ] **Docstrings or ADRs alongside code.** Non-obvious decisions captured in code or in `docs/`. *(Tip 13)*
- [ ] **Broken windows.** Commented-out code, `TODO` without issue link, dead branches. *(Tip 5)*

## Output format

Append to `${RUN_DIR}/review-report.md` (per-run artifact under `docs/aidp/runs/<id>/`; resolved via `RUN_DIR` env or `scripts/resolve-run.sh`) under a new section:

```
## Pragmatic Review Checklist (advisory)

### Decoupling
- [warning] Train wreck across module boundary. `src/orders/discount.py:42`
  Evidence: `customer.orders.find(id).totals.grandTotal -= d`
  Tip 44/46. See `.claude/rules/decoupling-and-configuration.md`.
  Recommendation: add `Customer.findOrder(id).applyDiscount(d)`.

### Resource ownership
- [advisory] Unbalanced file open. `src/shell/import.py:88`
  Evidence: `f = open(path, 'r')` with no `with` or `finally` on the early-return path at line 95.
  Tip 40. See `.claude/rules/assertions-and-invariants.md`.
```

If a section surfaces nothing, omit it. If nothing surfaces at all, write a single line: `Pragmatic checklist: clean. Residual concern: <one sentence or "none">.`

## Non-goals
- Does not replace `code-review`. Run that first; this is a second pass.
- Does not produce blocking findings. Escalations to `warning` cite an existing rule, but the rule's own enforcement (via `verify`) is what blocks.
- Does not cover process or team tips (estimation, retros, communication) — those are out of scope for a code pipeline.

## Reference
- Thomas & Hunt, *The Pragmatic Programmer: Your Journey to Mastery*, 20th Anniversary Edition, 2nd Edition.
- Mapping document: `docs/reference/pragmatic-tips-mapping.md`.
