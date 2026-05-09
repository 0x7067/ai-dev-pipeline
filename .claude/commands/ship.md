---
description: Ship a change end-to-end with mandatory TDD (research → plan → tdd-pre tests → implement → review → verify → smoke → release). Default mode is `fast` (risk-conditional plan gate, fast-low short-circuit). Pass `strict` for unconditional plan approval. Recommended primary entry point.
---

You are the orchestrator for `/ship`. Run the per-change pipeline end-to-end with approval gates and **mandatory test-driven development**, narrating progress between phases so the user sees real-time updates instead of a silent "Initializing…".

The orchestrator runs in the user's context (no `context: fork`). Each subagent invocation forks its own context via the Task tool. Between Task calls, the orchestrator prints a one-line phase marker visible to the user.

## Mode argument

`/ship` accepts an optional mode argument via `$ARGUMENTS`. The grammar is closed: only the modes below are valid (the canonical valid modes are: `<empty>` | `"strict"` | `"fast"` | `"research <topic>"`). TDD enforcement is unconditional and has no opt-out flag.

- `/ship` (no args) — `mode=fast`. Plan-approval gate is risk-conditional (halt only for `risk=medium` or `risk=high`). Research phase OFF. When `mode=fast` AND `risk=low` AND `change_class ∈ {trivial, config_only}`, the orchestrator engages the fast-low short-circuit (single approval at release; review folded into verify advisory).
- `/ship fast` — explicit form of the default; identical to `/ship` with no args. `mode=fast`.
- `/ship strict` — `mode=strict`. Plan-approval gate halts unconditionally regardless of risk tier. Research phase OFF.
- `/ship research <topic>` — `mode=fast` with `research=on`. Runs the research phase before planning, scoped to `<topic>` (free text, all remaining arguments).
- Literal `/ship adaptive`: hard error. Print to stderr the rejection narration `↷ unrecognized mode "adaptive"; valid modes are: <empty> | "strict" | "fast" | "research <topic>"` and stop with non-zero exit. No alias, no banner — the legacy `adaptive` mode was removed in v0.9.0 (see `CHANGELOG.md`).
- Anything else: print `↷ unrecognized mode "<value>"; valid modes are: <empty> | "strict" | "fast" | "research <topic>"` and stop. Do not proceed with a default — reject explicitly so users discover the new grammar instead of silently running with the wrong assumption.

Note: the default is selected by passing zero arguments (or the explicit `fast` token).

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
   # Replace the symlink atomically. `ln -sfn` updates an existing symlink
   # in place; the older `mv tmp-symlink existing-symlink` pattern is broken
   # on macOS — `mv` traverses the existing symlink and places the tmp
   # symlink INSIDE the target directory instead of replacing the symlink.
   ln -sfn "runs/$RUN_ID" docs/latest
   printf '%s\n' "$RUN_ID" > "docs/latest.txt.tmp.$_t" && mv "docs/latest.txt.tmp.$_t" docs/latest.txt
   printf '%s\n' "$RUN_ID" > ".claude/workflow-state/active.tmp.$_t" \
     && mv ".claude/workflow-state/active.tmp.$_t" .claude/workflow-state/active
   ```
   The `tmp+rename` pattern (still used for the two regular files) ensures readers never observe a half-written pointer; two concurrent `/ship` runs cannot consume each other's tmp files thanks to the per-process suffix. For `docs/latest`, `ln -sfn` is itself the atomic replacement primitive — it both creates and replaces the symlink in a single syscall.
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

Before phase 1, print the literal separator line `── Setup ──` so the user
sees a visual group boundary opening the Setup phase group (research → plan →
plan-approval → trivial-classification). Before phase 5 (TDD pre-phase), print
`── TDD ──`; if the change is classified `trivial` and TDD is skipped, print
`── TDD ──` immediately before phase 6 (implement) instead. Before phase 8
(verify), print `── Release ──` to open the Release phase group (verify →
smoke → release approval). These separators are additive narration only —
they MUST NOT replace, reorder, or modify any existing `▶`/`✓`/`✗`/`⏸`/`⏵`/`↷`
phase marker (R3 / AC9 / I1) and MUST NOT begin with `STATUS:` at column 0
(R2 / AC10 / I2).

1. **Research decision (1/8).**
   Research is OFF by default. Only run when EITHER:
   - the user invoked `/ship research <topic>` (explicit opt-in), OR
   - the planner's STATUS line later requests it (planner-driven escalation; orchestrator re-enters this phase before re-planning).

   Otherwise, print `↷ researcher skipped (default; pass /ship research <topic> to opt in)` and continue. Do NOT prompt the user — the previous unconditional skip-prompt is removed to keep the default fast path frictionless. When research IS run, invoke `researcher` per the phase contract.

   Under the fast-low short-circuit (`mode=fast` AND `risk=low` AND `change_class ∈ {trivial, config_only}`) the research phase prints `↷ researcher skipped (fast-low short-circuit)` without prompting.

2. **Plan (2/8).** Invoke `planner` per the phase contract. Capture risk tier from its STATUS line (`risk=<low|medium|high>`) and `change-type` from the plan's front-matter or planner STATUS (`trivial=true|false`).

3. **Plan approval gate.**
   - **A1 plan preview.** Before printing the `⏸ plan approval required …` line, run
     `bash scripts/preview.sh --anchor plan "${RUN_DIR}/current-plan.md"` and, if its
     stdout is non-empty, print the captured block fenced between two literal
     `── plan preview ──` divider lines so the user sees the four named sections
     (Risk Tier, Risk rationale, Acceptance Criteria, Boundary Map) — or the
     head-40 fallback — before deciding whether to approve. The preview is hard-
     capped at 60 lines; on missing/empty plan the helper emits nothing and the
     gate prints unchanged (fail-closed). The preview MUST NOT begin with
     `STATUS:` at column 0 (R2 / I2 enforced by the helper).
   - **Auto-promotion (`mode=fast` only).** Immediately after ingesting the planner STATUS line, inspect the planner-reported risk tier. If `mode=fast` AND `risk ∈ {medium, high}`: print `⏵ promoting fast → strict (risk=<tier>)` exactly once (one-shot, idempotent — never re-emit on subsequent phases) and set the in-memory mode to `strict` for the remainder of the run. The promotion does NOT abort the run; it continues into the strict-mode plan-approval branch below. From that point on the run behaves identically to one started with `/ship strict`.
   - If `mode=strict`: halt unconditionally. Print `⏸ plan approval required (run=$RUN_ID, mode=strict) — reply "approve" to continue, "reject" to stop`. Wait for explicit user approval.
   - If `mode=fast`:
     - For `risk=medium` or `risk=high`: (already promoted above) halt with the strict-mode prompt.
     - For `risk=low`: print `⏵ plan auto-approved (fast mode, risk=low) — pass /ship strict to force approval` and continue. When `risk=low` AND `change_class ∈ {trivial, config_only}` the orchestrator additionally engages the fast-low short-circuit: skip the plan-approval prompt entirely and skip the standalone review (folded into verify-report's `## Advisory Review` section); a single approval gate fires at release.

4. **Change-class classification (`trivial` | `config_only` | `standard`).**
   The orchestrator computes the **authoritative** `change_class` from the working tree, then cross-checks it against the planner's hint. The orchestrator value wins on disagreement (Resolution #1); record any disagreement in the run notes.

   Authoritative computation:

   ```
   base="$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo '')"
   if [ -z "$base" ]; then
     change_class=standard           # OD-2 fail-closed: no merge-base ⇒ standard
   else
     diff_files="$(git diff --name-only "$base")"
     change_class=config_only        # tentative
     while IFS= read -r f; do
       [ -z "$f" ] && continue
       case "$f" in
         *.md|*.yaml|*.yml|*.json) ;;
         .claude/agents/*|.claude/skills/*|.claude/rules/*|.claude/hooks/*) ;;
         *) change_class=standard ;;  # Resolution #3 fail-closed: any file outside the allowlist ⇒ standard
       esac
     done <<< "$diff_files"
   fi
   ```

   The config-only allowlist is exactly: `*.md`, `*.yaml`, `*.yml`, `*.json`, plus anything under `.claude/{agents,skills,rules,hooks}/**`. Any file outside that set forces `change_class=standard` regardless of how many config-allowlisted siblings sit alongside (mixed-diff fail-closed).

   Planner-hint reconciliation: also inspect `${RUN_DIR}/current-plan.md` front-matter for `change-type:` / `change-class:` and the planner STATUS `change-class=` token. The orchestrator's `git diff --name-only` value is authoritative; the planner hint is advisory.

   Then dispatch by class:

   - `change_class=trivial` (legacy carve-out — front-matter `change-type: trivial` AND/OR planner STATUS `trivial=true`):
   - Print `↷ TDD skipped (change-type=trivial) — see TDD Skip Rationale in ${RUN_DIR}/current-plan.md`.
   - Skip directly to phase 6 (Implement). The orchestrator MUST append the following block to `${RUN_DIR}/current-plan.md` BEFORE invoking the implementer (preserving any existing content; appended at end of file):
     ```
     ## TDD Skip Rationale

     trivial change (change-type=trivial); TDD pre-phase skipped per plan classification on <ISO-date>.
     ```
   - The implementer preserves this section verbatim when appending its `## Implementation` section.

   - `change_class=config_only` (orchestrator-authoritative, see computation above):
     - Print `↷ tester skipped (change_class=config_only)` and `↷ reviewer skipped (change_class=config_only)`. The orchestrator owns the skip decision; the tester and reviewer agents themselves contain no class-detection logic (Resolution OD-3, Option 1).
     - Skip the TDD pre-phase (phase 5) AND skip the standalone reviewer invocation (phase 7). Reviewer findings, if any are surfaced inline by the implementer, are folded into verify-report's `## Advisory Review` section instead of being written to `review-report.md`.
     - Verify (phase 8) runs in narrowed mode: only `bash scripts/validate-claude-config.sh` plus configured lint execute. Property/contract/full-suite gates self-skip via the `VERIFY_*_CMD=":"` empty-command path of `scripts/run-verification-gates.sh`. Concretely the orchestrator invokes the gate runner with the env-var profile preset:
       ```
       VERIFY_TYPECHECK_CMD=":" \
       VERIFY_LINT_CMD="bash scripts/validate-claude-config.sh" \
       VERIFY_SECURITY_CMD=":" \
       VERIFY_PROPERTY_CMD=":" \
       VERIFY_CONTRACT_CMD=":" \
       VERIFY_FULL_CMD=":" \
       bash scripts/run-verification-gates.sh
       ```
       `verify-report.md` is still produced (artifact contract preserved).
     - Proceed directly to phase 6 (Implement).

   - `change_class=standard` (default sibling tier; mixed diff or any file outside the allowlist): proceed to phase 5 normally. This is the fail-closed default.

   Otherwise (non-trivial), proceed to phase 5.

5. **TDD pre-phase: failing tests first (3/8).** Invoke `tester` per the phase contract with the environment variable `MODE=tdd-pre` (env var signal — chosen because it composes cleanly with the existing Task-tool argv contract and avoids touching the tester's argument parser).
   - Verify the tester's STATUS line includes both `expected_failing=N` and `failing=N` and that the two values are equal AND >0.
   - If `expected_failing` is missing, or `expected_failing != failing`, or `expected_failing == 0`: halt with `✗ tdd-pre invariant violated — expected_failing=<x> failing=<y>; halting`. Do not invoke the implementer.
   - Record the value of `expected_failing` (call it `N`). Snapshot the set of test files newly created by the tester via `git diff --name-only --diff-filter=A` between the pre- and post-tester commits (or working-tree state); pass this set to the implementer as the no-touch list.

6. **Implement (4/8).** Invoke `implementer` per the phase contract. Pass the prior tester report path (`${RUN_DIR}/test-report.md`) as input so the implementer can detect tdd-pre mode (presence of `## TDD-Pre Tests` section).
   - For non-trivial changes: verify the implementer's STATUS line includes `made_passing=M` and that `M == N` (the tester's `expected_failing`). If `made_passing` is missing or `M != N`: halt with `✗ tdd-post invariant violated — expected made_passing=<N>, got <M>; halting`.
   - For trivial changes: `made_passing` is not required.

7. **Review (5/8).** Invoke `reviewer` per the phase contract. Skipped when `change_class=config_only` (orchestrator owns the skip; agent itself contains no detection logic — Resolution OD-3, Option 1) and also folded into verify-report's `## Advisory Review` section when the fast-low short-circuit is engaged (`mode=fast` AND `risk=low` AND `change_class ∈ {trivial, config_only}`). When folded, the reviewer writes its findings into the verify-report instead of producing a standalone `review-report.md`; review is folded into verify advisory.
   - **A3 finding preview.** Immediately AFTER echoing the reviewer's
     `✓|✗ reviewer — STATUS:…` line, if `blocking>0` run
     `bash scripts/preview.sh --anchor review --top 3 --heading "## Blocking findings" "${RUN_DIR}/review-report.md"`
     and print up to 3 indented title lines under the STATUS echo;
     otherwise if `advisory>0`, run the same helper with anchor
     `"## Advisory findings"`. Missing report or anchor → no preview
     (fail-closed). Preview lines never start with `STATUS:` (I2).
   - If `blocking=0`, continue.
   - If `blocking>0`, return to step 6 (implementer) and loop. Maximum 3 review→implement loops; on the 4th unresolved blocking review, print `✗ review loop exceeded — halting` and stop.

8. **Verify (6/8).** Invoke `verifier` per the phase contract. The verifier itself runs `scripts/run-verification-gates.sh`, which streams per-gate `▶`/`✓`/`✗` lines. Note: an opt-in `verify → fix → verify` envelope is available via `MAX_VERIFY_RETRIES` and `VERIFY_RETRY_HINT_FILE`; see `.claude/rules/release-and-verification.md` ("Canonical Gate Runner") and the README "Tuning" section for details.
   - **A3 failing-gate preview.** After echoing the verifier's
     `✓|✗ verifier — STATUS:…` line, if STATUS state is not `go`, run
     `bash scripts/preview.sh --anchor verify --top 3 --heading "## Gate Results" "${RUN_DIR}/verify-report.md"`
     and print up to 3 indented gate titles under the STATUS echo.

9. **Final smoke gate (7/8).** Print `▶ smoke gate starting` and run:
   `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
   Print `✓ smoke gate ok` or `✗ smoke gate failed (rc=<code>)`.

10. **Release approval gate (8/8).** If verifier STATUS is `go` and smoke gate passed:
    - **Fast low-risk auto-approval.** If `mode=fast` AND plan `risk=low` AND review `blocking=0` AND all 6 verify gates green AND smoke gate passed, mark `STATUS: go` without halting and print `⏵ release auto-approved (fast, risk=low, all gates green)`. Continue to end-of-run summary. Under the fast-low short-circuit (`change_class ∈ {trivial, config_only}`) this single approval at release is the only gate that fires for the run (plan-approval prompt was skipped above; standalone review was folded into verify advisory).
    - **Otherwise** (strict mode, OR risk≥medium, OR any of the green-gate conditions above failed): halt and print `⏸ release approval required (run=$RUN_ID) — reply "approve" to continue, "reject" to stop`. Only mark the final Go decision after explicit user approval.

## Stop conditions

Stop immediately on any unresolved blocking outcome. Print a final summary of which phases completed and which did not.

## End-of-run artifact summary

After all phases finish (success, halt, or stop condition), render the
end-of-run artifact summary block as the very last output. Follow
`docs/templates/end-of-run-summary-template.md` exactly: absolute paths,
checklist of produced artifacts (plan — now includes the implementer's appended
`## Implementation` section, specs, research, test-report, test-results.json,
review-report, verify-report, refactor-report, audit-report),
and only print lines for artifacts that exist on disk. The block is shared
verbatim across `/ship`, `/review`, `/refactor`, `/audit`, `/research`.
