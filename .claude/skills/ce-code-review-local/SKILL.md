---
name: ce-code-review-local
description: Local override for the marketplace `ce-code-review` skill's best-judgment fixer path. Replaces the single-implementer heterogeneous queue with batched 3-pass dispatch (safe_auto → gated_auto → manual-with-fix), eager per-finding evidence precheck, and an enforced `${RUN_DIR}/fixer-pass-<class>.json` sidecar. Invoke when the user picks "Auto-resolve with best judgment" in this repo. Triggers on the same hand-offs as the marketplace skill's option B route.
---

# ce-code-review-local

## Purpose

Local override skill for the `ce-code-review` marketplace skill's auto-fix path.
Extends the marketplace skill's "Auto-resolve with best judgment" option with
batched 3-pass dispatch, eager per-finding evidence precheck, and enforced
structured sidecar output.

This skill is invoked **instead of** the marketplace fixer when the user picks
"Auto-resolve with best judgment" in this repository. The marketplace skill's
read-only cache is not modified.

## When to Use

- User has run `ce-code-review` (marketplace) and accepted findings.
- User selects the "Auto-resolve with best judgment" action.
- This repo is the consumer — do not apply this skill to other repositories
  without verifying that `scripts/lib/fixer-core.sh` and
  `scripts/parse-fixer-pass.sh` are present.

## 3-Pass Dispatch Protocol

### Prerequisites

- `RUN_DIR` exported and pointing to the current run directory.
- `scripts/lib/fixer-core.sh` on disk (source it to get the core helpers).
- `scripts/parse-fixer-pass.sh` on disk (executable).
- `jq` available on PATH (required for queue partition; parser has a bash fallback).

### Step 1 — Partition the Queue

Source `scripts/lib/fixer-core.sh` and call `fixer_partition_queue` with the
full JSON array of findings from the review output:

```sh
source scripts/lib/fixer-core.sh
partition_output="$(fixer_partition_queue "$findings_json")"
```

The function emits three labeled sections (safe_auto, gated_auto, manual) to
stdout. Parse the output into three arrays — one per class.

### Step 2 — Eager Precheck

For each finding across all three groups (before dispatching any pass):

```sh
# Shell reads the ±5-line window around file:line
start=$(( line - 5 )); start=$(( start < 1 ? 1 : start ))
window_text="$(sed -n "${start},$((line + 5))p" "$file" 2>/dev/null || true)"

# Core checks — no I/O in core
for token in "${evidence[@]}"; do
  result="$(fixer_precheck_finding "$window_text" "$token")"
  if [ "$result" = "stale" ]; then
    # Route finding to failed immediately; remove from its pass queue
    ...
  fi
done
```

Stale findings are removed from their class queue and recorded in a pre-pass
`failed` list (they will appear in the sidecar's `failed[]` array).

### Step 3 — Pass 1 (safe_auto)

Invoke the `implementer` agent with the `<fixer-queue class="safe_auto">` envelope
containing only the safe_auto findings (post-precheck). The implementer writes
its sidecar to `${RUN_DIR}/fixer-pass-safe_auto.json`.

After the implementer returns, parse its sidecar:

```sh
bash scripts/parse-fixer-pass.sh "${RUN_DIR}/fixer-pass-safe_auto.json"
parse_rc=$?
```

- Exit 0 → sidecar valid; extract `applied_count` and `failed_count`.
- Exit 1 → schema error; treat as orchestrator error (`error_flag=1`).
- Exit 2 → sidecar absent (implementer crashed/did not complete); treat as `error_flag=1`.

### Step 4 — Gate Pass 2

Source `scripts/lib/fixer-core.sh` and call the gating predicate:

```sh
gate="$(fixer_gate_pass "$applied_count" "$failed_count" "$error_flag")"
```

- `run` → proceed to Pass 2.
- `skip` → skip Pass 2 (and transitively Pass 3 unless policy allows; default: skip).

### Step 5 — Pass 2 (gated_auto)

If gated as `run`, dispatch the implementer with `<fixer-queue class="gated_auto">`.
Parse sidecar, gate, then proceed to Pass 3 by the same pattern.

### Step 6 — Pass 3 (manual)

Manual-class findings have machine-suggested fixes but require human oversight.
Dispatch the implementer with `<fixer-queue class="manual">`. The implementer
applies fixes but human review of the sidecar output is expected before merging.

### Step 7 — Aggregate and Report

Collect all three sidecars' `applied[]` and `failed[]` entries. Emit a summary
to the review report:

```
Pass 1 (safe_auto):  applied=N  failed=M
Pass 2 (gated_auto): applied=N  failed=M  [skipped]
Pass 3 (manual):     applied=N  failed=M  [skipped]
Stale (precheck):    N findings routed to failed before dispatch
```

## Failure Handling

| Failure | Behavior |
|---------|----------|
| Sidecar absent (exit 2) | Set `error_flag=1`; gate skips next pass; all queued findings for that pass route to `failed` |
| Schema violation (exit 1) | Set `error_flag=1`; same as sidecar absent |
| All findings stale in a class | Queue for that pass is empty; pass is skipped (nothing to dispatch) |
| `verify_cmd` failure | Isolated to the finding; implementer handles it; pass continues |

## References

- Core helpers: `scripts/lib/fixer-core.sh`
- Boundary parser: `scripts/parse-fixer-pass.sh`
- Sidecar schema: `docs/schemas/fixer-pass-v1.schema.json`
- Implementer fixer-queue mode: `.claude/agents/implementer.md` §Fixer-Queue Mode
- FC/IS rules: `.claude/rules/architecture-fcis.md`
- Boundary parsing rules: `.claude/rules/boundary-parse-dont-validate.md`

## Deferral: Upstream Contribution

The `fixer-queue` envelope and `verify_cmd` field are additive extensions to the
finding schema. Upstreaming to the `ce-code-review` marketplace skill is tracked
as a future task (out of scope for this change).
