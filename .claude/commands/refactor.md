---
description: Refactor code without behavior change — with pre/post verification gates and human approval, narrating progress.
---

You are the orchestrator for `/refactor`. The invariant is **no behavior change**. Run the refactor pipeline as explicit subagent invocations with progress narration, so the user sees real-time updates instead of a silent "Initializing…".

The orchestrator runs in the user's context (no `context: fork`). Each subagent invocation forks its own context via the Task tool.

## Step 0: mint run-id and export environment
Same protocol as `/ship` step 0:
- Reuse `RUN_ID` if already set (validated through `${CLAUDE_PLUGIN_ROOT}/scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`; else `RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`.
- `export RUN_ID` and `export RUN_DIR="docs/runs/${RUN_ID}"`.
- Create `${RUN_DIR}` and update `docs/latest`, `docs/latest.txt`, `.claude/workflow-state/active` atomically (`tmp + mv`).
- Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/prune-runs.sh"` (no-op when `CI=true`).
- Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

Every Task subagent invocation in subsequent phases MUST inherit `RUN_ID` and `RUN_DIR`. Approval prompts MUST include `run=$RUN_ID`.

## Phase contract
Same as `/ship`: print `▶ <phase> starting (<n>/<total>)` before, echo `✓` or `✗` plus the STATUS body after.

## Sequential phases

1. **Pre-refactor gate (1/5).** Print `▶ pre-refactor gate starting` and run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-verification-gates.sh"`
   The script streams per-gate lines. If any gate fails, print `✗ pre-refactor gate — clean baseline required, aborting` and stop. A clean baseline is mandatory before any refactor.

2. **Coverage precondition gate.** Print `▶ coverage precondition starting`. Determine the refactor target glob: prefer `$ARGUMENTS` when present; otherwise prompt the user for a target file/glob (e.g. `src/foo.py`). Run:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/coverage-precondition.sh" <target>`
   - exit 0 → print `✓ coverage precondition ok` and continue. The script appended a `## Coverage Precondition` section to `${RUN_DIR}/.refactor-precondition.md`; the planner/reviewer MUST fold that fragment into `${RUN_DIR}/refactor-report.md`.
   - exit 1 → print `✗ coverage precondition blocked — see stderr; aborting` and stop. Do not proceed to planning.
   - exit 2 → invalid configuration; print the script's stderr and stop.

3. **Plan (2/5).** Invoke `planner` per the phase contract with refactor framing. The plan must describe structural changes only; any functional diff is a blocking violation that the planner must surface.

4. **Plan approval gate (scope-aware).** Compute the refactor scope and decide whether a halt is required.

   - Source thresholds from `${CLAUDE_PLUGIN_ROOT}/.claude/policy/approvals.yaml` via `${CLAUDE_PLUGIN_ROOT}/scripts/parse-approvals-policy.sh` (typed key=value form). Defaults if the policy file is absent: `files=10, loc=300`.
   - Compute scope inputs from the planner's diff (file count + LOC delta).
   - Classify via the pure core function `refactor_scope_classify` in `${CLAUDE_PLUGIN_ROOT}/scripts/lib/hitl-core.sh`:
     `bash -c 'source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/hitl-core.sh"; refactor_scope_classify "$FILES" "$LOC" "$FILES_THR" "$LOC_THR"'`
     Result is `above` or `below`.
   - On `above`: halt with the two-line halt grammar (line 1 = halt
     summary, line 2 = wrapped `scope=above-threshold (files=N, loc=N)`):

     ```
     ⏸ refactor plan approval required (run=$RUN_ID)
       scope=above-threshold (files=<N>, loc=<N>)
     ```

     Then invoke `AskUserQuestion` (per `.claude/rules/decision-surfacing.md`,
     option #1 ends with `(Recommended)`; each option's `description`
     should state the consequence in plain language):

     ```
     AskUserQuestion:
       question: "Approve the refactor plan? (run=$RUN_ID, scope=above-threshold)"
       options:
         - label: "Approve (Recommended)"
           description: continue to Implement; record verb=approve
         - label: "Reject"
           description: stop the run; record verb=reject
       allow_other: false
     ```

     Append one record to `${RUN_DIR}/decisions.jsonl` via
     `${CLAUDE_PLUGIN_ROOT}/scripts/append-decision.sh` with `gate=refactor-plan, verb=<approve|reject>`
     after the user's reply.
   - On `below`: print `↷ refactor plan gate skipped (scope below threshold)` and proceed without a halt. The pre-existing pre/post verification gates remain unchanged.

   Per HITL plan invariant 1 (fail-closed), if the policy parser errors or the diff cannot be measured, treat as `above` and halt — never silently skip.

5. **Implement (3/5).** Invoke `implementer` per the phase contract.

6. **Review (4/5).** Invoke `reviewer` per the phase contract. The reviewer must confirm the diff is structural-only; if a behavior change is detected, treat as blocking and halt.

7. **Verify (5/5).** Invoke `verifier` per the phase contract (post-refactor gate).

## Stop conditions
Stop immediately on any unresolved blocking finding. The pre-refactor gate failing is non-recoverable: a refactor cannot start from a red baseline.

## End-of-run artifact summary

After all phases finish (success, halt, or stop condition), render the
end-of-run artifact summary block as the very last output. Follow
`${CLAUDE_PLUGIN_ROOT}/docs/templates/end-of-run-summary-template.md` exactly: absolute paths,
checklist of produced artifacts, and only print lines for artifacts that
exist on disk. The block is shared verbatim across `/ship`, `/review`,
`/refactor`, `/audit`, `/research`.
