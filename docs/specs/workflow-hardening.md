## Goal
Align workflow verification gates, artifacts, and validation checks to a strict baseline.

## Scope
- Canonical verification gate runner
- Strict artifact enforcement
- Fast hooks for edit-time checks

## Non-Goals
- Product functionality changes

## Risks
- Increased process strictness for empty artifacts

## Acceptance Criteria
- Strict smoke gate passes when artifacts are populated.
- Gate order and artifacts are deterministic.
