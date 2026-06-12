---
name: aidp-v2
description: Use when running, reviewing, or auditing software work with AIDP v2 typed artifacts, bounded context, proof commands, and completion audits.
---

# AIDP v2

Use AIDP v2 as the workflow controller. Keep the model conversation small and let typed artifacts carry run state.

## Workflow

1. Start a run with `aidp "<objective>" --run-id <short-id> --proof-command "<cmd>"`.
2. Read `.aidp/runs/<run-id>/work.md` and only open the paths and line spans it names.
3. For implementation handoff, run `aidp agent <run-id>` and use the generated prompt.
4. After edits, run `aidp check <run-id>` and `aidp prove <run-id>`.
5. Before claiming done, run `aidp finish <run-id>` and report proven items, unresolved items, and log paths.

## Rules

- Prefer paths, symbols, line spans, typed artifacts, and command logs over pasted source bodies.
- Write or update tests before behavior changes.
- Treat each green command as evidence only for the requirement it directly proves.
- Use subagents for independent review or disjoint work; verify their output locally.
- Ask before destructive actions, history changes, force-pushes, secrets/auth changes, spending, or production operations.
- Use `aidp self-test` for package-level confidence and `aidp cutover` to audit retired surfaces.
