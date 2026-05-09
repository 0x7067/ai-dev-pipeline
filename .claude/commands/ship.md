---
description: Ship one change with the lean path: optional research -> plan -> implement -> review -> verify -> smoke -> release. Default mode is auto; pass `strict` to require explicit approvals.
---

You are the orchestrator for `/ship`. Keep the run moving. Use the smallest pipeline that still leaves a plan, implementation notes, review, tool-gate evidence, and a release decision.

## Arguments

Accepted forms:

- `/ship` or `/ship auto` - default. Research is off. Plan approval is automatic for `risk=low`; `risk=medium` and `risk=high` require approval before implementation.
- `/ship strict` - require explicit approval before implementation and before release, regardless of risk.
- `/ship research <topic>` - run research first, then continue in `auto` mode.

Reject anything else with:

`↷ unrecognized mode "<value>"; valid modes are: <empty> | "auto" | "strict" | "research <topic>"`

`/ship fast` is legacy; `/ship adaptive` is legacy. Reject both with the same message. Do not alias them.

## Step 0: Run Identity

Before any phase, create a run directory and export the run environment:

```sh
if [ -n "${RUN_ID:-}" ]; then
  RUN_ID="$(bash scripts/parse-run-id.sh "$RUN_ID")"
elif [ -n "${GITHUB_RUN_ID:-}" ]; then
  RUN_ID="$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash scripts/mint-run-id.sh)"
else
  RUN_ID="$(bash scripts/mint-run-id.sh)"
fi
export RUN_ID
export RUN_DIR="docs/runs/${RUN_ID}"
mkdir -p "$RUN_DIR" "$RUN_DIR/research" "$RUN_DIR/specs" .claude/workflow-state
_t="$$.${RANDOM:-0}"
ln -sfn "runs/$RUN_ID" docs/latest
printf '%s\n' "$RUN_ID" > "docs/latest.txt.tmp.$_t" && mv "docs/latest.txt.tmp.$_t" docs/latest.txt
printf '%s\n' "$RUN_ID" > ".claude/workflow-state/active.tmp.$_t" && mv ".claude/workflow-state/active.tmp.$_t" .claude/workflow-state/active
bash scripts/prune-runs.sh
printf '▶ run minted RUN_ID=%s RUN_DIR=%s\n' "$RUN_ID" "$RUN_DIR"
```

Every Task subagent receives `RUN_ID` and `RUN_DIR`.

## Phase Contract

For each subagent phase:

1. Print `▶ <phase> starting (<n>/<total>)`.
2. Invoke the named subagent with the user's request and prior artifacts.
3. Echo its final `STATUS:` line as `✓ <phase> - ...` for `ok`/`go`, otherwise `✗ <phase> - ...`.

## Lean Phases

1. **Research (optional).** Run `researcher` only for `/ship research <topic>` or when planning blocks and explicitly requests research. Otherwise print `↷ research skipped (default)`.

2. **Plan.** Run `planner`. It writes `${RUN_DIR}/current-plan.md` and returns `risk=<low|medium|high|unknown>`.
   - Before any approval prompt, preview the plan with:
     `bash scripts/preview.sh --anchor plan "${RUN_DIR}/current-plan.md"`.
   - In `auto` mode, continue without a prompt when `risk=low`.
   - In `auto` mode with `risk=medium` or `risk=high`, halt with `⏸ plan approval required (run=$RUN_ID, risk=<tier>) - reply "approve" to continue, "reject" to stop`.
   - In `strict` mode, halt with `⏸ plan approval required (run=$RUN_ID, mode=strict) - reply "approve" to continue, "reject" to stop`.

3. **Implement.** Run `implementer`. It edits the source tree and appends `## Implementation` to `${RUN_DIR}/current-plan.md`.

4. **Review.** Run `reviewer`. If `blocking=0`, continue. If `blocking>0`, return to Implement once. If blocking findings remain after one fix pass, halt with `✗ review blocked - unresolved blocking findings`.
   - After the reviewer status, preview up to three findings:
     `bash scripts/preview.sh --anchor review --top 3 --heading "## Blocking findings" "${RUN_DIR}/review-report.md"`.

5. **Verify.** Run `verifier`. It runs `bash scripts/run-verification-gates.sh` and writes `${RUN_DIR}/verify-report.md`.
   - If verifier returns anything other than `STATUS: go`, preview failed gates with:
     `bash scripts/preview.sh --anchor verify --top 3 --heading "## Gate Results" "${RUN_DIR}/verify-report.md"`.
   - Stop on `no-go` or `fail`.

6. **Smoke.** Run:
   `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
   Print `✓ smoke gate ok` or `✗ smoke gate failed (rc=<code>)`.

7. **Release.**
   - In `auto` mode, if risk is `low`, review has `blocking=0`, verifier is `go`, and smoke passed, print `⏵ release auto-approved (auto, risk=low, gates green)` and finish.
   - Otherwise halt with `⏸ release approval required (run=$RUN_ID) - reply "approve" to finish, "reject" to stop`.

## Run Manifest (final step)

After all phases complete (success or halt), emit the per-run manifest as the final orchestration step. Strictly additive — failure here MUST NOT change the release decision already taken.

```sh
bash scripts/write-manifest.sh \
  --command ship \
  --mode "${SHIP_MODE:-auto}" \
  --risk-tier "${PLAN_RISK:-unknown}" \
  --status "${RUN_STATUS:-ok}" \
  || printf '↷ manifest emit skipped (rc=%d)\n' "$?"
```

The writer reads `RUN_ID`/`RUN_DIR`, hashes every artifact under `RUN_DIR`, and writes `${RUN_DIR}/manifest.json` atomically. Schema: `docs/schemas/run-manifest/v1/manifest.schema.json`. Boundary parser for any future consumer: `scripts/parse-manifest.sh`.

## Stop Conditions

Stop on missing required artifacts, unresolved blocking review findings, failed verification, failed smoke, or rejected approval. Print which phase stopped and why.

## End-of-Run Summary

After success or halt, render `docs/templates/end-of-run-summary-template.md` as the final output. Include only artifacts that exist.
