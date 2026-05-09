---
description: Ship one change with the lean path: optional research -> plan -> implement -> review -> verify -> smoke -> release. Default mode is auto; pass `strict` to require explicit approvals.
---

You are the orchestrator for `/ship`. Keep the run moving. Use the smallest pipeline that still leaves a plan, implementation notes, review, tool-gate evidence, and a release decision.

## Arguments

Accepted forms:

- `/ship` or `/ship auto` - default. Research is off. Plan approval is automatic for `risk=low`; `risk=medium` and `risk=high` require approval before implementation.
- `/ship strict` - require explicit approval before implementation and before release, regardless of risk.
- `/ship research <topic>` - run research first, then continue in `auto` mode.
- `/ship queue` - at the next halt, write a pending-approval marker via `scripts/queue-pending-approval.sh` and exit 0 with `STATUS: queued`. A subsequent `/ship` resume reads the marker (parsed via `scripts/parse-pending-approval.sh`) and proceeds.

Halts may take an optional `time-box=<seconds>` modifier. The orchestrator stores the deadline; when `time_box_resolve` (core, in `scripts/lib/hitl-core.sh`) reports `expired=true`, the orchestrator auto-rejects the halt and records `actor=time-box, verb=reject, rationale=elapsed` in `${RUN_DIR}/decisions.jsonl`. Default is OFF; opt-in per halt only.

Reject anything else with:

`↷ unrecognized mode "<value>"; valid modes are: <empty> | "auto" | "strict" | "queue" | "research <topic>"`

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

## Step 0.5: Policy Load (boundary parse)

Load the approval policy via the typed boundary parser. Per
`.claude/rules/boundary-parse-dont-validate.md` and the HITL plan, the
orchestrator NEVER reads `approvals.yaml` directly — it routes through
the parser, which fails closed on malformed input.

```sh
POLICY_FILE="${POLICY_FILE:-.claude/policy/approvals.yaml}"
if [ -f "$POLICY_FILE" ]; then
  if ! POLICY_KV="$(bash scripts/parse-approvals-policy.sh "$POLICY_FILE" 2>&1)"; then
    printf '✗ approvals policy invalid; refusing to run\n%s\n' "$POLICY_KV" >&2
    exit 2
  fi
  export POLICY_KV
else
  printf '↷ policy file not found at %s; using built-in defaults\n' "$POLICY_FILE"
  POLICY_KV=""
fi
```

`POLICY_KV` is the typed key=value form. Consumers grep specific keys
(e.g. `release_gate.auto_approve_when.risk`) — they NEVER re-read the
YAML. Decisions are sourced from this typed form via `policy_apply` in
`scripts/lib/hitl-core.sh`.

## Phase Contract

For each subagent phase:

1. Print `▶ <phase> starting (<n>/<total>)`.
2. Invoke the named subagent with the user's request and prior artifacts.
3. Echo its final `STATUS:` line as `✓ <phase> - ...` for `ok`/`go`, otherwise `✗ <phase> - ...`.

## Lean Phases

1. **Research (optional).** Run `researcher` only for `/ship research <topic>` or when planning blocks and explicitly requests research. Otherwise print `↷ research skipped (default)`.

2. **Plan.** Run `planner`. It writes `${RUN_DIR}/current-plan.md` and emits a STATUS line containing `risk=<low|medium|high|unknown>` and `risk_reason=<phrase>`.
   - Parse the planner's STATUS line via `bash scripts/parse-status-line.sh "<line>"` — this is the SINGLE STATUS-line parser; do not grep STATUS lines directly.
   - Render the rationale banner (single line, no ANSI in committed artifacts):
     `risk=<tier> because <reason>` — reason sourced from the parsed `risk_reason` field; defaults to `(unspecified)` for backward compatibility.
   - Before any approval prompt, preview the plan with:
     `bash scripts/preview.sh --anchor plan "${RUN_DIR}/current-plan.md"`.
   - In `auto` mode, continue without a prompt when `risk=low`.
   - In `auto` mode with `risk=medium` or `risk=high`, halt with `⏸ plan approval required (run=$RUN_ID, risk=<tier> because <reason>) - reply "approve" to continue, "edit <comment>" to revise, "reject" to stop`.
   - In `strict` mode, halt with `⏸ plan approval required (run=$RUN_ID, mode=strict, risk=<tier> because <reason>) - reply "approve" / "edit <comment>" / "reject"`.
   - On `edit <comment>`: re-invoke the `planner` with the comment as additional input; record the event in `${RUN_DIR}/decisions.jsonl` with `gate=plan, verb=edit, plan_hash=<hash of new plan>` via `scripts/append-decision.sh`. The plan gate is the ONLY gate that accepts `edit` (HITL plan invariant 8); the release gate accepts `approve | reject` only.
   - On any plan-gate transition, append one record to `${RUN_DIR}/decisions.jsonl`:
     `bash scripts/append-decision.sh --run-dir "$RUN_DIR" --ts "$(date -u +%FT%TZ)" --actor user --gate plan --verb <approve|edit|reject> --rationale "<short>" --plan-hash "<hash>"`

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
   - Compute the release decision via the pure core function `policy_apply` in `scripts/lib/hitl-core.sh`. Capture BOTH stdout (the verdict) AND stderr (the audit-clarity signal) — `policy_apply` emits `reject-reason=<verifier-crashed|gates-failed|smoke-failed>` on stderr whenever the verdict is `reject`, and is silent on stderr for `auto-approve`/`prompt`:

     ```sh
     _err="$RUN_DIR/.policy_apply.stderr.$$"
     verdict=$(bash -c 'source scripts/lib/hitl-core.sh; policy_apply "$SHIP_MODE" "$PLAN_RISK" "$REVIEW_BLOCKING" "$VERIFY_STATUS" "$SMOKE_STATUS"' 2>"$_err")
     reject_reason=$(sed -n 's/^reject-reason=//p' "$_err" | head -n1)
     rm -f "$_err"
     ```

     The function returns `auto-approve | prompt | reject`. Per HITL plan invariant 1 (auto-approve safety), any malformed/unrecognized input fails closed to `prompt` or `reject` — NEVER `auto-approve`.
   - On `auto-approve`: print `⏵ release auto-approved (auto, risk=low, gates green)`, append a decision record with `actor=auto, gate=release, verb=approve, rationale="all gates green"`, and finish.
   - On `prompt`: halt with `⏸ release approval required (run=$RUN_ID) - reply "approve" to finish, "reject" to stop`. The release gate accepts ONLY `approve | reject` (HITL plan invariant 8 — `edit` is plan-gate only). On the user's response, the rationale recorded is the user's own short reason (or `"user approved"` / `"user rejected"` when none was given) — `reject_reason` from `policy_apply` is NOT relevant here because `prompt` had no machine reject.
   - On `reject`: print `✗ release rejected (${reject_reason:-policy})`, record `verb=reject` with `rationale="${reject_reason:-policy}"`, do not finish. The `reject_reason` MUST be one of `verifier-crashed | gates-failed | smoke-failed` (the typed values `policy_apply` emits); if absent or unrecognized, fall back to the literal `policy` so the audit log never carries arbitrary stderr bytes.
   - On every release-gate transition append exactly one record:
     `bash scripts/append-decision.sh --run-dir "$RUN_DIR" --ts "$(date -u +%FT%TZ)" --actor <user|auto> --gate release --verb <approve|reject> --rationale "<short>" --plan-hash "${PLAN_HASH:-}"`

## Queue Mode (`/ship queue`)

When `SHIP_MODE=queue`, at the next halt the orchestrator does NOT block.
Instead it writes a pending-approval marker via the atomic writer
(`scripts/queue-pending-approval.sh`, tempfile + rename) and exits 0
with a `STATUS: queued | ...` line. A subsequent `/ship` resume reads
the marker via the typed parser (`scripts/parse-pending-approval.sh`)
— the orchestrator NEVER reads the marker file directly.

```sh
if [ "${SHIP_MODE:-auto}" = "queue" ]; then
  bash scripts/queue-pending-approval.sh \
    --run-dir "$RUN_DIR" \
    --run-id "$RUN_ID" \
    --gate plan \
    --plan-hash "${PLAN_HASH:-}" \
    --created-at "$(date -u +%FT%TZ)"
  bash scripts/append-decision.sh \
    --run-dir "$RUN_DIR" \
    --ts "$(date -u +%FT%TZ)" \
    --actor auto --gate plan --verb reject \
    --rationale "queued for async approval" \
    --plan-hash "${PLAN_HASH:-}"
  printf 'STATUS: queued | risk=%s | pending approval marker written | report=%s\n' \
    "${PLAN_RISK:-unknown}" "$RUN_DIR/.pending-approval.json"
  exit 0
fi
```

On resume:

```sh
if [ -f "$RUN_DIR/.pending-approval.json" ]; then
  PENDING_KV="$(bash scripts/parse-pending-approval.sh "$RUN_DIR/.pending-approval.json")" \
    || { printf '✗ pending-approval marker invalid; refusing to resume\n' >&2; exit 2; }
  # PENDING_KV contains run_id, gate, deadline_iso, plan_hash, created_at — typed.
fi
```

## Time-Box Modifier

A halt MAY take an optional `time-box=<seconds>` modifier. The
orchestrator records `deadline = now + seconds` and, between user-input
polls, evaluates the pure core function `time_box_resolve now deadline`
from `scripts/lib/hitl-core.sh`. On `expired=true` the orchestrator
auto-rejects the halt and records:
`actor=time-box, gate=<plan|release>, verb=reject, rationale=elapsed`.

Default is OFF; opt-in per halt only. The policy bounds (min/max
seconds) are sourced from the typed `POLICY_KV` (`time_box.min_seconds`,
`time_box.max_seconds`) — never from raw YAML.

## Promote `latest-green` (post-release, pre-manifest)

After the release decision is taken, advance the `latest-green` pointer set
when the run ended fully green (verifier `STATUS: go` AND reviewer
`blocking=0`). Strictly additive — this never touches the existing
`latest`/`active` pointers and never changes the release decision.

`VERIFY_STATUS` is captured from the verifier's STATUS line in step 5;
`REVIEW_BLOCKING` is the integer from the reviewer's STATUS line in step 4.
On non-green runs the script no-ops (rc=0). Failure of the script is logged
and ignored.

```sh
bash scripts/promote-latest-green.sh \
  --run-id "$RUN_ID" \
  --verify-status "${VERIFY_STATUS:-fail}" \
  --review-blocking "${REVIEW_BLOCKING:-1}" \
  || printf '↷ promote skipped (rc=%d)\n' "$?"
```

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
