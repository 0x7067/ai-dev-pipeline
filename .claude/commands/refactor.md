---
description: Refactor code without behavior change — with pre/post verification gates and human approval, narrating progress.
---

You are the orchestrator for `/refactor`. The invariant is **no behavior change**. Run the refactor pipeline as explicit subagent invocations with progress narration, so the user sees real-time updates instead of a silent "Initializing…".

The orchestrator runs in the user's context (no `context: fork`). Each subagent invocation forks its own context via the Task tool.

## Step 0: mint run-id and export environment
Same protocol as `/ship` step 0:
- Reuse `RUN_ID` if already set (validated through `scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash scripts/mint-run-id.sh)`; else `RUN_ID=$(bash scripts/mint-run-id.sh)`.
- `export RUN_ID` and `export RUN_DIR="docs/runs/${RUN_ID}"`.
- Create `${RUN_DIR}` and update `docs/latest`, `docs/latest.txt`, `.claude/workflow-state/active` atomically (`tmp + mv`).
- Run `bash scripts/prune-runs.sh` (no-op when `CI=true`).
- Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

Every Task subagent invocation in subsequent phases MUST inherit `RUN_ID` and `RUN_DIR`. Approval prompts MUST include `run=$RUN_ID`.

## Phase contract
Same as `/ship`: print `▶ <phase> starting (<n>/<total>)` before, echo `✓` or `✗` plus the STATUS body after.

## Sequential phases

1. **Pre-refactor gate (1/5).** Print `▶ pre-refactor gate starting` and run:
   `bash scripts/run-verification-gates.sh`
   The script streams per-gate lines. If any gate fails, print `✗ pre-refactor gate — clean baseline required, aborting` and stop. A clean baseline is mandatory before any refactor.

2. **Coverage precondition gate.** Print `▶ coverage precondition starting`. Determine the refactor target glob: prefer `$ARGUMENTS` when present; otherwise prompt the user for a target file/glob (e.g. `src/foo.py`). Run:
   `bash scripts/coverage-precondition.sh <target>`
   - exit 0 → print `✓ coverage precondition ok` and continue. The script appended a `## Coverage Precondition` section to `${RUN_DIR}/.refactor-precondition.md`; the planner/reviewer MUST fold that fragment into `${RUN_DIR}/refactor-report.md`.
   - exit 1 → print `✗ coverage precondition blocked — see stderr; aborting` and stop. Do not proceed to planning.
   - exit 2 → invalid configuration; print the script's stderr and stop.

3. **Plan (2/5).** Invoke `planner` per the phase contract with refactor framing. The plan must describe structural changes only; any functional diff is a blocking violation that the planner must surface.

4. **Plan approval gate.** Halt and print `⏸ refactor plan approval required (run=$RUN_ID) — reply "approve" to continue, "reject" to stop`. Wait for explicit user approval before any code edits.

5. **Implement (3/5).** Invoke `implementer` per the phase contract.

6. **Review (4/5).** Invoke `reviewer` per the phase contract. The reviewer must confirm the diff is structural-only; if a behavior change is detected, treat as blocking and halt.

7. **Verify (5/5).** Invoke `verifier` per the phase contract (post-refactor gate).

## Stop conditions
Stop immediately on any unresolved blocking finding. The pre-refactor gate failing is non-recoverable: a refactor cannot start from a red baseline.

## End-of-run artifact summary

After all phases finish (success, halt, or stop condition), render the
end-of-run artifact summary block as the very last output. Follow
`docs/templates/end-of-run-summary-template.md` exactly: absolute paths,
checklist of produced artifacts, and only print lines for artifacts that
exist on disk. The block is shared verbatim across `/ship`, `/review`,
`/refactor`, `/audit`, `/research`.
