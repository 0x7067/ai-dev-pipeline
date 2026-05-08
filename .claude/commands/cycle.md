---
description: Run full workflow plan -> implement -> review -> test -> verify, narrating progress between phases.
---

You are the orchestrator for `/cycle`. Run the per-change pipeline as a sequence of explicit subagent invocations, narrating progress between phases so the user sees real-time updates instead of a silent "Initializing…".

The orchestrator runs in the user's context (no `context: fork`). Each subagent invocation forks its own context via the Task tool. Between Task calls, the orchestrator prints a one-line phase marker visible to the user.

## Phase contract
For every phase X with subagent name `<agent>`:

1. Print the start marker: `▶ <phase> starting (<n>/<total>)`
2. Invoke the `<agent>` subagent via the Task tool. Pass the user's request and any prior phase reports as needed.
3. The subagent's final line is `STATUS: <state> | … | report=<path>`. Echo it to the user as:
   - `✓ <phase> — <STATUS body>` if STATUS state is `ok`/`go`
   - `✗ <phase> — <STATUS body>` otherwise

## Sequential phases

1. **Research decision (1/6).**
   Ask the user whether to run research before planning. Recommend research if any risk signal (security/auth/authz, data integrity, release-critical behavior, cross-module refactor) or scope signal (multi-system changes, unclear requirements, boundary parser updates across multiple ingress points) is present; recommend skipping when both are low and scope is contained.
   - If user confirms: invoke `researcher` per the phase contract.
   - If user skips: print `↷ researcher skipped` and continue.

2. **Plan (2/6).** Invoke `planner` per the phase contract. Capture risk tier from its STATUS line (`risk=<low|medium|high>`).

3. **Plan approval gate.** Halt and require explicit user approval before continuing. Print `⏸ plan approval required — reply "approve" to continue, anything else to stop`.

4. **Implement (3/6).** Invoke `implementer` per the phase contract.

5. **Review (4/6).** Invoke `reviewer` per the phase contract.
   - If the STATUS line shows `blocking=0`, continue.
   - If `blocking>0`, return to step 4 (implementer) and loop. Maximum 2 review→implement loops; on the 3rd unresolved blocking review, print `✗ review loop exceeded — halting` and stop.

6. **Test (5/6).** Invoke `tester` per the phase contract.
   - If STATUS shows `failing>0`: retry the tester up to 3 times for flaky failures, prefixing each retry with `↻ tester retry <n>/3` and including triage notes from the prior STATUS line. After 3 failed retries, treat as blocking and stop.

7. **Verify (6/6).** Invoke `verifier` per the phase contract. The verifier itself runs `scripts/run-verification-gates.sh`, which streams per-gate `▶`/`✓`/`✗` lines.

8. **Final smoke gate.** After verifier returns, print `▶ smoke gate starting` and run:
   `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
   Print `✓ smoke gate ok` or `✗ smoke gate failed (rc=<code>)`.

## Stop conditions
Stop immediately on any unresolved blocking outcome. Print a final summary of which phases completed and which did not.
