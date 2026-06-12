# AGENTS.md

## AIDP v2

Use the typed AIDP kernel as the project workflow surface:

- Start work with `aidp "<objective>" --run-id <short-id> --proof-command "<cmd>"`.
- Read `.aidp/runs/<run-id>/work.md`; keep context to listed paths and line spans.
- Implement the smallest task slice, then run `aidp check <run-id>` and `aidp prove <run-id>`.
- Finish with `aidp finish <run-id>` and report status, proven items, unresolved items, and log paths.

## Working Rules

- Use Basic Memory before non-trivial work: `search_notes`, then `read_note` or `build_context` when needed. Save durable decisions, fixes, conventions, and lessons with `write_note`; no secrets.
- Use `rtk` for shell commands and `rtk rg` for search. Use `uv` for Python commands.
- Write tests before behavior changes. Keep edits scoped to the objective and preserve unrelated worktree changes.
- Ask before destructive actions, history changes, force-pushes, secrets/auth changes, spending, or production operations. Retired surface deletion requires explicit approval immediately before the patch.
- Run `aidp cutover` before deletion discussions; it inventories retired candidates without mutating files.
- Prefer subagents for independent read-heavy review/research or disjoint implementation slices; avoid parallel write conflicts and verify their output locally.

## Verification

For AIDP changes, run:

```sh
uv run pytest -q
uv run aidp self-test
uv run aidp cutover
```

`uv run pytest -q` covers the v2 package, command lifecycle, plugin surface, and completion audit.
