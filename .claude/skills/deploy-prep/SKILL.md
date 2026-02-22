---
name: deploy-prep
description: Prepare release metadata and deployment readiness checks in a reusable, tool-agnostic way.
disable-model-invocation: true
---

# Deploy Prep

## Objective
Prepare release-ready metadata once verification gates pass.

## Steps
1. Confirm blocking gates are green.
2. Confirm working tree policy is satisfied for target project.
3. Generate or update release notes/changelog.
4. Record deployment checklist and rollback notes.

## Output
- `docs/deploy-report.md`

## Note
This skill is intentionally manual-first for safety in reusable templates.
