---
description: Ship a change end-to-end with mandatory TDD (research → plan → tdd-pre tests → implement → review → verify → smoke → release). Default mode is `adaptive` (risk-conditional plan gate). Pass `strict` for unconditional plan approval. Recommended primary entry point.
---

You are the orchestrator for `/ship`. Run the per-change pipeline end-to-end with approval gates and **mandatory test-driven development**, narrating progress between phases so the user sees real-time updates instead of a silent "Initializing…".

The orchestrator runs in the user's context (no `context: fork`). Each subagent invocation forks its own context via the Task tool. Between Task calls, the orchestrator prints a one-line phase marker visible to the user.

## Mode argument

`/ship` accepts an optional mode argument via `$ARGUMENTS`. The grammar is closed: only two modes are valid. TDD enforcement is unconditional and has no opt-out flag.

- `/ship` (no args) — `mode=adaptive`. Plan-approval gate is risk-conditional (halt only for `risk=medium` or `risk=high`).
- `/ship strict` — `mode=strict`. Plan-approval gate halts unconditionally regardless of risk tier.
- Anything else (including `/ship tdd`, `/ship adaptive`, `/ship anything`): print `↷ unrecognized mode "<value>"; valid modes are: <empty> | "strict"` and stop. Do not proceed with a default — reject explicitly so users discover the new grammar instead of silently running with the wrong assumption.

Note: literal `/ship adaptive` is rejected (not silently mapped). The default is selected by passing zero arguments.

## Step 0: mint run-id, prune, export environment

Before any phase runs, the orchestrator MUST execute step 0 in this order. This is what makes concurrent `/ship` sessions safe to run on the same repo.

1. **Mint or import RUN_ID.**
   - If `RUN_ID` is already set in the environment, validate it through `scripts/parse-run-id.sh` and reuse it.
   - Else if `GITHUB_RUN_ID` is set (CI), translate it: run
     `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash scripts/mint-run-id.sh)` so the parser-valid timestamp+sha+disambiguator wraps the CI number into the canonical regex (the disambiguator becomes `printf '%02x' $((GITHUB_RUN_ID % 256))`).
   - Else: `RUN_ID=$(bash scripts/mint-run-id.sh)`.
2. **Export the run env.** `export RUN_ID` and `export RUN_DIR="docs/runs/${RUN_ID}"`. Every Task subagent invocation in subsequent phases MUST receive these in its environment so all artifact writes go to `${RUN_DIR}/`.
3. **Create the run directory and update pointers atomically:**
   ```
   mkdir -p "$RUN_DIR" "$RUN_DIR/research" "$RUN_DIR/specs" .claude/workflow-state
   _t="$$.${RANDOM:-0}"
   ( cd docs && ln -sfn "runs/$RUN_ID" "latest.tmp.$_t" && mv "latest.tmp.$_t" latest )
   printf '%s\n' "$RUN_ID" > "docs/latest.txt.tmp.$_t" && mv "docs/latest.txt.tmp.$_t" docs/latest.txt
   printf '%s\n' "$RUN_ID" > ".claude/workflow-state/active.tmp.$_t" \
     && mv ".claude/workflow-state/active.tmp.$_t" .claude/workflow-state/active
   ```
   The `tmp+rename` pattern with a per-process suffix is required: readers must never observe a half-written pointer, and two concurrent `/ship` runs must not consume each other's tmp files.
4. **Retention.** Run `bash scripts/prune-runs.sh` (no-op when `CI=true`). Default keeps 10 newest runs; never deletes the active or latest run.
5. **Surface the run-id.** Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

Once step 0 completes, every subsequent approval prompt MUST include the run-id, e.g. `⏸ plan approval required (run=$RUN_ID, risk=medium) …`. Every Task subagent invocation MUST inherit `RUN_ID` and `RUN_DIR`.

## Phase contract

For every phase X with subagent name `<agent>`:

1. Print the start marker: `▶ <phase> starting (<n>/<total>)`
2. Invoke the `<agent>` subagent via the Task tool. Pass the user's request and any prior phase reports as needed.
3. The subagent's final line is `STATUS: <state> | … | report=<path>`. Echo it as:
   - `✓ <phase> — <STATUS body>` if STATUS state is `ok`/`go`
   - `✗ <phase> — <STATUS body>` otherwise

## Sequential phases (TDD pipeline)

1. **Research decision (1/8).**
   Ask the user whether to run research before planning. Recommend research if any risk signal (security/auth/authz, data integrity, release-critical behavior, cross-module refactor) or scope signal (multi-system changes, unclear requirements, boundary parser updates across multiple ingress points) is present; recommend skipping when both are low and scope is contained.
   - If user confirms: invoke `researcher` per the phase contract.
   - If user skips: print `↷ researcher skipped` and continue.

2. **Plan (2/8).** Invoke `planner` per the phase contract. Capture risk tier from its STATUS line (`risk=<low|medium|high>`) and `change-type` from the plan's front-matter or planner STATUS (`trivial=true|false`).

3. **Plan approval gate.**
   - If `mode=strict`: halt unconditionally. Print `⏸ plan approval required (run=$RUN_ID, mode=strict) — reply "approve" to continue, "reject" to stop`. Wait for explicit user approval.
   - If `mode=adaptive`:
     - For `risk=medium` or `risk=high`: halt and print `⏸ plan approval required (run=$RUN_ID, risk=<tier>) — reply "approve" to continue, "reject" to stop`. Wait for explicit user approval.
     - For `risk=low`: print `⏵ plan auto-approved (adaptive mode, risk=low) — pass /ship strict to force approval` and continue.

4. **Trivial-change classification.**
   Inspect `${RUN_DIR}/current-plan.md` front-matter for `change-type: trivial` AND/OR check planner STATUS for `trivial=true`. If either signal is present, the change is classified `trivial`:
   - Print `↷ TDD skipped (change-type=trivial) — see TDD Skip Rationale in ${RUN_DIR}/impl-summary.md`.
   - Skip directly to phase 6 (Implement). The orchestrator MUST emit the following two lines into `${RUN_DIR}/impl-summary.md` BEFORE invoking the implementer (preserving any existing content):
     ```
     ## TDD Skip Rationale

     trivial change (change-type=trivial); TDD pre-phase skipped per plan classification on <ISO-date>.
     ```
   - The implementer's template-rendering step preserves this section.

   Otherwise (non-trivial), proceed to phase 5.

5. **TDD pre-phase: failing tests first (3/8).** Invoke `tester` per the phase contract with the environment variable `MODE=tdd-pre` (env var signal — chosen because it composes cleanly with the existing Task-tool argv contract and avoids touching the tester's argument parser).
   - Verify the tester's STATUS line includes both `expected_failing=N` and `failing=N` and that the two values are equal AND >0.
   - If `expected_failing` is missing, or `expected_failing != failing`, or `expected_failing == 0`: halt with `✗ tdd-pre invariant violated — expected_failing=<x> failing=<y>; halting`. Do not invoke the implementer.
   - Record the value of `expected_failing` (call it `N`). Snapshot the set of test files newly created by the tester via `git diff --name-only --diff-filter=A` between the pre- and post-tester commits (or working-tree state); pass this set to the implementer as the no-touch list.

6. **Implement (4/8).** Invoke `implementer` per the phase contract. Pass the prior tester report path (`${RUN_DIR}/test-report.md`) as input so the implementer can detect tdd-pre mode (presence of `## TDD-Pre Tests` section).
   - For non-trivial changes: verify the implementer's STATUS line includes `made_passing=M` and that `M == N` (the tester's `expected_failing`). If `made_passing` is missing or `M != N`: halt with `✗ tdd-post invariant violated — expected made_passing=<N>, got <M>; halting`.
   - For trivial changes: `made_passing` is not required.

7. **Review (5/8).** Invoke `reviewer` per the phase contract.
   - If `blocking=0`, continue.
   - If `blocking>0`, return to step 6 (implementer) and loop. Maximum 2 review→implement loops; on the 3rd unresolved blocking review, print `✗ review loop exceeded — halting` and stop.

8. **Verify (6/8).** Invoke `verifier` per the phase contract. The verifier itself runs `scripts/run-verification-gates.sh`, which streams per-gate `▶`/`✓`/`✗` lines. Note: an opt-in `verify → fix → verify` envelope is available via `MAX_VERIFY_RETRIES` and `VERIFY_RETRY_HINT_FILE`; see `.claude/rules/release-and-verification.md` ("Canonical Gate Runner") and the README "Tuning" section for details.

9. **Final smoke gate (7/8).** Print `▶ smoke gate starting` and run:
   `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
   Print `✓ smoke gate ok` or `✗ smoke gate failed (rc=<code>)`.

10. **Release approval gate (8/8).** If verifier STATUS is `go` and smoke gate passed, halt and print `⏸ release approval required (run=$RUN_ID) — reply "approve" to continue, "reject" to stop`. Only mark the final Go decision after explicit user approval.

## Stop conditions

Stop immediately on any unresolved blocking outcome. Print a final summary of which phases completed and which did not.

## End-of-run artifact summary

After all phases finish (success, halt, or stop condition), render the
end-of-run artifact summary block as the very last output. Follow
`docs/templates/end-of-run-summary-template.md` exactly: absolute paths,
checklist of produced artifacts (plan, specs, research, test-report,
review-report, verify-report, impl-summary, refactor-report, audit-report),
and only print lines for artifacts that exist on disk. The block is shared
verbatim across `/ship`, `/review`, `/refactor`, `/audit`, `/research`.
