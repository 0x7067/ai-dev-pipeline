# Persistent Feature Specs

This directory holds the **long-lived mirror** of feature specs produced by
the `planner` agent. When the planner writes
`${RUN_DIR}/specs/<feature>.md` for a feature change, it ALSO writes a
byte-identical copy here as `docs/artifacts/specs/<feature>.md`.

## Why this exists

Per-run artifacts under `docs/runs/<RUN_ID>/` are pruned by
`scripts/prune-runs.sh`. A persistent mirror lets a feature spec survive
beyond its originating run, so future runs can reference it. This is the
low-cost SPDD borrow #1 from
`docs/runs/20260510T150126-666528-5c/research/spdd-pivot.md`.

## Current contract (write-only)

In the current pipeline release the mirror is **write-only / advisory**:

- The planner writes here when (and only when) a feature spec is
  produced for a run.
- No agent reads these files yet. There is therefore **no boundary
  parser** for this directory in this run.
- Concurrent writes resolve last-writer-wins via tempfile + `mv`.

The moment any agent starts reading `docs/artifacts/specs/<feature>.md`,
that read becomes a new untrusted-input boundary and **must** be guarded
by a typed `parse_feature_spec` function (see the future-parsers table in
the SPDD-borrows plan). Do not add a reader without the parser.

## See also

- `.claude/agents/planner.md` (`<persistent-spec-mirror>` block)
- `.claude/rules/boundary-parse-dont-validate.md`
- `docs/runs/20260510T150126-666528-5c/research/spdd-pivot.md`
