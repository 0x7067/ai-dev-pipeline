# Release and Verification Rules

## Run Artifact Anchoring
- `RUN_DIR` is always absolute, rooted at `${AIDP_ARTIFACTS_ROOT}/runs/<id>/`.
- `AIDP_PROJECT_ROOT` and `AIDP_ARTIFACTS_ROOT` are derived once by `scripts/lib/project-root.sh` and exported at the top of `/ship`. The project root comes from `CLAUDE_PROJECT_DIR` (fallback `$(pwd)`). The artifacts root is `${project}/docs/aidp` unconditionally for every caller.
- Pointer files (`latest`, `latest.txt`, `latest-green.txt`) live under `AIDP_ARTIFACTS_ROOT`; the workflow-state pointer (`.claude/workflow-state/active`) lives under `AIDP_PROJECT_ROOT`. Helper scripts (`mint-run-id.sh`, `prune-runs.sh`, `smoke-bootstrap.sh`) must keep these paths absolute; a relative `RUN_DIR` is rejected by `smoke-bootstrap.sh`.
- Rationale: `harness_cd_repo_root` anchors plugin self-checks to the plugin checkout; run artifacts must stay inside the consumer project and not pollute its top-level `docs/`.

## Gate Policy
- Blocking: type errors, test failures, security findings at error severity.
- Advisory: warnings (tracked but non-blocking in v1).

## Gate Authority
- Only CI-tier gates are authoritative. Pre-commit hooks and local runs are convenience layers and may be bypassed (`--no-verify`).
- A change is "verified" only when `scripts/run-verification-gates.sh` has exited 0 in CI on the merge commit.
- Source: appxlab, "Quality Gates for AI-Generated Code: CI/CD Pipeline Guide" (2026-04-06).

## Workflow-Gate Bypass (in-band token)
The `PreToolUse` hook `.claude/hooks/workflow-gate.sh` blocks `Agent`
invocations of `implementer`, `reviewer`, `tester`, and `verifier` when the
prerequisite phase in `.claude/workflow-state/active` is not marked
`completed: true`. Outside a live `/ship` run — for example when an abandoned
state file lingers from a prior session, or for non-coding edits that still
benefit from the FC/IS-specialized agent — the gate would otherwise force a
fallback to `general-purpose`, silently dropping the agent's specialization.

To opt out per-call, prefix the agent prompt with a literal token:

```
[gate-bypass: <non-empty reason>]
```

Rules:

- The token must appear within the first 200 characters of `tool_input.prompt`
  (anchored, so it cannot hide inside pasted content).
- The reason must be non-empty after whitespace trim.
- On any parse failure, the gate falls through to normal phase enforcement
  (fail closed).
- Each honored bypass appends one JSON record
  (`{timestamp, agent_type, reason, run_id}`) to
  `${RUN_DIR:-/tmp}/gate-bypass.log` for audit.
- `WORKFLOW_GATES_SKIP=1` and `/reset` remain alternative bypasses
  (session-wide and stale-state-clearing, respectively).

Appropriate uses: out-of-band human approval, ad-hoc work on a stale
workflow-state, non-coding edits routed through `implementer`. Inappropriate
uses: skipping a real `/ship` plan-approval gate that is in progress — that
is what the `strict` mode is for.

## Plan-Gate Bypass

The `PreToolUse` hook `.claude/hooks/plan-gate.sh` blocks `Edit`/`Write` tool calls
when no plan artifact exists for the current run. Two environment variables control
its behaviour (see the comment block at the top of `plan-gate.sh`):

- `PLAN_GATE_BYPASS=1` — skip the gate for the current invocation (no audit record written).
- `PLAN_GATE_MODE=warn|off|block` (default `block`) — change the enforcement level:
  - `block`: exit 2 to reject the tool call.
  - `warn`: print to stderr but allow the call through.
  - `off`: disable the gate entirely for this session.

Pass conditions that bypass the gate automatically (no env var needed):
- The project has not opted in (no `.claude/policy/approvals.yaml` found).
- The target path is a pipeline meta-file (`.claude/`, `docs/`, `scripts/`, etc.).
- The edit is trivially shaped (test/spec file, lockfile, single-line diff, comment-only diff).
- `workflow-state` reports `phases.plan.completed == true`.
- `${RUN_DIR}/current-plan.md` exists and is non-empty.

Appropriate uses of `PLAN_GATE_BYPASS=1`: one-off fixes to pipeline plumbing, rapid iteration
on non-product code that does not benefit from the full `/ship` cycle.

## Verification Signals
- Blocking signals must be tool-derived: compile/typecheck, lint, test, SAST.
- Model self-critique is advisory and never blocking. The `review` skill produces advisory findings; the `verify` skill produces the go/no-go decision from tool exit codes.
- Source: AgentPatterns, "Verification-Centric Development for AI-Generated Code"; Sonar, "The future is AC/DC" (2026-03-02).

## Risk Tiers
- `low`: routine change with bounded blast radius.
- `medium`: cross-module behavior change or non-trivial refactor.
- `high`: security-sensitive, data-integrity, auth/authz, or release-critical change.

## Human Approval Policy (modes: auto, strict)
- The authoritative source for approval policy is `.claude/policy/approvals.yaml`. The orchestrator parses it via `scripts/parse-approvals-policy.sh` (typed boundary parser); the rule prose below is a human-readable summary of what that file encodes.
- In `/ship auto` (the default), `risk=low` plans proceed without a prompt. `risk=medium` and `risk=high` require plan approval before implementation.
- In `/ship strict`, plan approval and release approval are always explicit.
- The release gate auto-approves only when ALL of these are true: mode is `auto`, plan risk is `low`, review has `blocking=0`, verification is green, and smoke passed. The decision is computed by the pure core function `policy_apply` in `scripts/lib/hitl-core.sh`; any malformed input fails closed (never `auto-approve`). The orchestrator prints `⏵ release auto-approved (auto, risk=low, gates green)`.
- Plan-gate verbs: `approve | edit | reject`. Release-gate verbs: `approve | reject` (no `edit`). Every gate transition appends one record to `${RUN_DIR}/decisions.jsonl` per `docs/templates/decisions-jsonl-schema.md`.
- Legacy `/ship fast` and `/ship adaptive` tokens are rejected. Use `/ship`, `/ship strict`, `/ship queue`, or `/ship research <topic>`.

## Verification Sequence
1. Type check / compile
2. Lint
3. Security scan (if configured)
4. Property-based tests
5. Contract tests
6. Full test suite

## Canonical Gate Runner
- Use `bash scripts/run-verification-gates.sh` as the single source of truth for gate execution order.
- Allow overrides via environment variables for project-specific commands.
- Bounded retry: `MAX_VERIFY_RETRIES` (default `1`) enables a `verify → fix → verify` envelope. The runner sleeps `VERIFY_RETRY_SLEEP_S` (default `2`) seconds between attempts. On gate failure the runner writes `{gate, exit_code, attempt}` to `VERIFY_RETRY_HINT_FILE` (default `${RUN_DIR}/.verify-retry.json`) for the `verify` skill to consume on the next pass. CI may pin `MAX_VERIFY_RETRIES=0` to make gate failure immediate and deterministic.

## Evidence Quality
- Every verification or review claim must include evidence.
- Sources must prioritize official documentation.
- Maximum two external non-official sources when needed.
- Numeric impact claims without evidence are invalid and treated as advisory at minimum.

## Output Artifacts
Per-run reports are written inside `RUN_DIR` (see "Run Artifact Anchoring" above) — i.e. `${AIDP_ARTIFACTS_ROOT}/runs/<id>/<name>-report.md` (`docs/aidp/runs/<id>/…`):

- `${RUN_DIR}/test-report.md` — `test-gen` skill
- `${RUN_DIR}/verify-report.md` — `static-analysis` skill
- `${RUN_DIR}/review-report.md` — `code-review` skill
- `${RUN_DIR}/refactor-report.md` — `refactor` skill
- `${RUN_DIR}/audit-report.md` — `auditor` agent

Template (repo-level, not per-run):
- `docs/templates/workflow-assessment-report-template.md`

## Reuse Guidance
- Keep commands tool-agnostic and auto-detect available package manager/runtime.
- Expose project overrides through environment variables when needed.
- Keep templates parameterized so they can be copied across repositories.
