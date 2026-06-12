# CLAUDE.md

This repository uses AIDP v2. Read `AGENTS.md` first and treat it as the
workflow contract for this repo.

## Workflow

- Start with `aidp "<objective>" --run-id <short-id> --proof-command "<cmd>"`.
- Use `.aidp/runs/<run-id>/work.md` for bounded context and implementation scope.
- Run `aidp check <run-id>` and `aidp prove <run-id>` after edits.
- Run `aidp finish <run-id>` before claiming completion.
- Run `aidp cutover` before deletion discussions; it audits candidates without deleting them.

## Verification

For AIDP changes, run:

```sh
uv run pytest -q
uv run aidp self-test
uv run aidp cutover
```
