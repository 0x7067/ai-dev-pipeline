# ai-dev-pipeline

AIDP v2 is a typed, agentic kernel for AI-assisted development with bounded context and direct proof. It records Goal, context, constraints, and done-when in versioned artifacts, then requires line spans, command logs, and typed artifacts before a run can finish.

## Default Flow

```sh
aidp "<objective>" --run-id <run-id> --proof-command "<command>"
aidp agent <run-id>
aidp check <run-id>
aidp prove <run-id>
aidp finish <run-id>
```

The bare objective command creates `.aidp/runs/<run-id>/contract.json`, `context.json`, `plan.json`, `events.jsonl`, and a compact `work.md`. The agent handoff prints an executable prompt that references the packet instead of embedding source bodies.

## Commands

| Command | Purpose |
|---|---|
| `aidp doctor` | Detect project languages, package manager, and likely proof commands. |
| `aidp "<objective>"` | Start a run and write a compact worker packet. |
| `aidp plan "<objective>"` | Create typed run artifacts without writing a worker packet. |
| `aidp work <run-id>` | Regenerate `.aidp/runs/<run-id>/work.md` from artifacts. |
| `aidp agent <run-id>` | Print and persist an executable agent prompt. |
| `aidp check <run-id>` | Validate typed artifacts and schema versions. |
| `aidp prove <run-id>` | Run proof commands and store command evidence. |
| `aidp finish <run-id>` | Block unless every done-when requirement has direct evidence. |
| `aidp adapter codex` | Render compact Codex `AGENTS.md` guidance for the v2 flow. |
| `aidp self-test` | Run hermetic docs-only and code/test scenarios against the v2 lifecycle. |
| `aidp cutover` | Print a non-destructive audit for retired surfaces before any deletion patch. |

## Artifacts

Every run lives under `.aidp/runs/<run-id>/`.

| Artifact | Role |
|---|---|
| `contract.json` | Objective, constraints, risk, unsafe actions, and done-when requirements. |
| `context.json` | Bounded source pointers, detected commands, citations, and omitted context. |
| `plan.json` | Expected tasks, test-first notes, and proof commands. |
| `work.md` | Compact worker packet for an implementation agent. |
| `agent.md` | Executable handoff prompt generated from the packet. |
| `evidence.json` | Command evidence, changed files, review results, risks, and verdict. |
| `events.jsonl` | Append-only lifecycle events. |

Schemas for the typed artifacts live in `docs/v2/`.

## Plugin

This repo is an installable Codex plugin. The manifest lives at `.codex-plugin/plugin.json`, and the workflow skill lives under `skills/aidp-v2/`.

## Verification

For changes to AIDP itself, run:

```sh
uv run pytest -q
uv run aidp self-test
uv run aidp cutover
```

`uv run pytest -q` covers the v2 package, command lifecycle, plugin surface, and completion audit. `aidp self-test` proves both docs-only and code/test scenarios through `agent`, `check`, `prove`, and `finish`. `aidp cutover` should report a clean retired-surface audit before release.

## Design

The ground-up redesign is documented in `docs/redesign/2026-06-12-ground-up-ai-dev-pipeline.md`.
