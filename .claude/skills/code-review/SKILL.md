---
name: code-review
description: Perform severity-first code review with FC/IS, security, and correctness lenses. Use when reviewing code changes, assessing architecture compliance, or checking for security issues.
---

# Code Review

## Review Lenses
- Architecture boundaries (core/shell/boundary)
- Boundary parsing compliance
- Security and secrets hygiene
- Correctness and edge cases
- Test adequacy and invariant coverage

## Output Format
- Findings ordered by severity.
- Each finding includes file path and rationale.
- Explicitly state residual risk if no finding exists.

## Blocking Conditions
- Raw ingress data used in core/domain logic.
- Missing parser at a documented boundary.
- Untested critical invariant.
