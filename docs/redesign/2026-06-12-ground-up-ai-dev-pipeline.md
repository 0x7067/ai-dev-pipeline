# Ground-Up AI Development Pipeline Redesign

## Decision

AIDP v2 is the repo's only workflow surface. It is a small Python package and Codex plugin that turns an objective into typed run artifacts, a compact worker packet, proof commands, and a completion audit.

The kernel owns run state, context packaging, gates, evidence, and finish criteria. Agent surfaces provide model labor through generated prompts and skills; they do not own policy or artifact truth.

## Product Shape

Default command:

```text
aidp "<objective>"
```

Explicit commands:

```text
aidp plan "<objective>"
aidp work <run-id>
aidp agent <run-id>
aidp check <run-id>
aidp prove <run-id>
aidp finish <run-id>
aidp doctor
aidp self-test
aidp cutover
```

The human sees one concise status stream and one evidence bundle. Long logs stay in files and are referenced by path.

## Plugin Shape

The installable Codex plugin consists of:

```text
.codex-plugin/plugin.json
skills/aidp-v2/SKILL.md
src/aidp/
tests/aidp/
docs/v2/
```

The manifest exposes the plugin as **AI Dev Pipeline** in the Productivity category. The skill teaches Codex to start runs, read bounded worker packets, execute proof commands, and finish only after the typed audit passes.

## Core Model

Every run produces typed artifacts under `.aidp/runs/<run-id>/`:

1. `contract.json` - objective, constraints, done-when, risk, and unsafe actions.
2. `context.json` - bounded file/source pointers, command inventory, citations, and omitted-context notes.
3. `plan.json` - ordered tasks, expected changed paths, tests-first notes, review focus, and proof commands.
4. `evidence.json` - commands run, exit codes, changed files, review results, unresolved risks, and completion verdict.

Append-only events live in `events.jsonl`. Human-readable markdown is generated from typed artifacts and never treated as source of truth.

## Architecture

```text
src/aidp/
  cli.py
  models.py
  detect.py
  context_pack.py
  gates.py
  finish.py
  work.py
  check.py
  selftest.py
  cutover.py
  adapters/
    codex.py
tests/
  aidp/
docs/
  v2/
```

Python stdlib is enough for the runtime. Tests use `pytest`.

## Operating Rules

- Ask at most one question, only when the next action is unsafe or ambiguous in a way that would cause rework.
- Prefer single-agent execution for small, well-scoped work. Use subagents for explicit parallel review/research or disjoint implementation slices.
- Always build a compact context pack before planning. The pack contains paths, line spans, commands, and citations; it does not copy large file bodies.
- Use tests-first for behavior changes. If no automated test is practical, the plan must name the proof command or manual smoke signal before work starts.
- Treat verification as a typed completion audit. A green command is evidence only for the requirement it actually covers.
- Keep generated status short. Long logs go to files, and evidence summaries point to those files.
- Keep the public surface installable: package metadata, plugin manifest, skill, docs, and tests must agree.

## Friction Budget

Default happy path:

1. User gives objective.
2. Kernel derives contract and context pack.
3. Agent writes or confirms a task plan.
4. Agent implements task slices with tests first.
5. Kernel validates typed artifacts, runs proof commands, and records evidence.
6. Agent returns a concise completion audit.

Human prompts appear only for destructive actions, secrets/auth changes, spending/prod actions, force/history operations, or medium/high-risk plan approval.

## Token Budget

- Context pack defaults stay small and cite paths or spans instead of file bodies.
- Subagent summaries return findings with file/line references and no raw dumps.
- Repeated tool output is compacted into command, exit code, first failure, and log path.
- Durable guidance belongs in `AGENTS.md` or skills; per-run artifacts carry only facts needed for that run.

## Verification

```sh
uv run pytest -q
uv run aidp self-test
uv run aidp cutover
python3 /Users/pedro/.codex/skills/.system/plugin-creator/scripts/validate_plugin.py .
```
