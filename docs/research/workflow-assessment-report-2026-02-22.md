# Workflow Assessment Report

Date: 2026-02-22
Scope: Claude Code workflow scaffolding in this repository (`CLAUDE.md`, `.claude/`, `scripts/`, and `docs/templates/`).

## 1. Evidence Summary
- Official sources:
  - Claude Code best practices (Explore -> Plan -> Implement loop and verification-first guidance): https://docs.claude.com/en/docs/claude-code/best-practices
  - Claude Code common workflows (Plan Mode and workflow usage patterns): https://docs.claude.com/en/docs/claude-code/common-workflows
  - Claude Code settings (scope files, precedence, shared project config): https://docs.claude.com/en/docs/claude-code/settings
  - Claude Code hooks reference (JSON stdin contract, event model, exit-code behavior): https://docs.claude.com/en/docs/claude-code/hooks
  - Claude Code subagents (isolation model and frontmatter contract): https://docs.claude.com/en/docs/claude-code/sub-agents
  - Claude Code agent teams (experimental status, approval patterns, quality gates): https://docs.claude.com/en/docs/claude-code/agent-teams
  - Anthropic engineering patterns for orchestrator-worker and human checkpointing: https://www.anthropic.com/engineering/building-effective-agents
- External sources (max 2):
  - NIST AI RMF (governance framing for human oversight and risk control): https://www.nist.gov/itl/ai-risk-management-framework
- Repo-local evidence:
  - `CLAUDE.md` defines FC/IS, boundary parsing, and reusable command flow.
  - `.claude/commands/cycle.md` defines a bounded loop and stop condition.
  - `.claude/rules/release-and-verification.md` defines risk tiers, human approvals, verification order, and evidence policy.
  - `scripts/validate-claude-config.sh` and `scripts/smoke-bootstrap.sh` passed on 2026-02-22.
- Source gaps:
  - No `src/` tree exists yet, so boundary policy execution is validated only at script/scaffolding level.
  - Human approval checkpoints are policy-defined but not yet machine-enforced by a dedicated report-quality gate script.

## 2. Current-State Assessment
- Strengths:
  - Clear phase orchestration exists (`/plan` -> `/implement` -> `/review` -> `/test` -> `/verify`) with bounded retry in `.claude/commands/cycle.md`.
  - Specialized agents have distinct responsibilities and deliverables in `.claude/agents/`.
  - Verification ordering and blocking/advisory semantics are explicit in `.claude/rules/release-and-verification.md`.
  - Reusable templates now codify risk profile, checkpoints, evidence, and retry triage in `docs/templates/`.
  - Bootstrap smoke checks enforce required workflow artifacts in `scripts/smoke-bootstrap.sh`.
- Weaknesses:
  - Human approvals are still process-driven, not hard-gated by automated checks.
  - Evidence quality policy exists, but no script validates non-empty citations in generated reports.
  - Boundary enforcement currently returns `skipped` while no `src/` directory exists, which can create false confidence for production readiness.

- Rubric scores:

| Category | Score (0-5) | Evidence | Gaps | Recommended Action |
|---|---:|---|---|---|
| Orchestration clarity | 4 | Explicit command chain and bounded loop in `.claude/commands/cycle.md` | No automated check that loop-count and checkpoint fields are present in output docs | Add report-quality validator that checks required sections/fields |
| Skill/subagent separation quality | 4 | Distinct agent roles and skill wiring under `.claude/agents/` | No drift test ensuring each agent deliverable is actually produced and non-empty | Add artifact presence and non-empty checks |
| Human oversight quality | 3 | Checkpoints defined in templates and rules | No deterministic gate that blocks go/no-go when approvals are missing | Enforce checkpoint fields in verify report via script |
| Verification rigor | 4 | Deterministic sequence + blocking/advisory policy + validation scripts | Boundary check currently scaffold-level only; no explicit security-scan adapter command yet | Add configurable security check command and activate boundary checks once `src/` exists |
| Reusability/portability | 4 | Dynamic tool detection and template-based outputs | Reuse metadata/KPI capture not yet standardized | Add optional metrics file schema and CI export |

- Average score: 3.8/5
- Grade: B+
- Recommendation: Go for continued template rollout, with P0 automation of evidence/checkpoint enforcement before production-scale use.

## 3. Risk Register
| Risk | Severity | Likelihood | Detection | Mitigation | Owner |
|---|---|---|---|---|---|
| Human approvals skipped in fast-moving cycles | High | Medium | Missing fields in verify artifacts | Add blocking validator for approval fields in verify report | Workflow maintainer |
| Unsourced claims in review/verify outputs | Medium | Medium | Manual doc inspection | Add citation-presence and source-count checks | Reviewer/verifier owner |
| False confidence from scaffold-only boundary checks | Medium | High (current state) | `boundary-check: skipped` output | Require enabling boundary checks after first `src/` module lands | Implementer + verifier |
| Drift between templates and actual agent outputs | Medium | Medium | Incomplete/empty report files | Add non-empty artifact checks in smoke script | Workflow maintainer |
| Team overhead if experimental agent teams enabled too early | Medium | Low | Token/time increase, unstable coordination | Keep teams off by default; enable only with explicit criteria | Tech lead |

## 4. Target Workflow (Research -> Plan -> Implement -> Verify)
### Research
- Inputs:
  - Current task request, relevant code paths, existing policies/rules, official docs.
- Activities:
  - Explore codebase in read-only mode first.
  - Gather official docs evidence and up to two external governance references when needed.
  - Capture assumptions and uncertainty explicitly.
- Exit criteria:
  - Evidence set is complete.
  - No unverified numerical claims remain.
  - Scope and risk tier draft exists.

### Plan
- Inputs:
  - Research findings, risk tier proposal, acceptance criteria.
- Activities:
  - Produce decision-complete plan with FC/IS mapping, boundary parser map, failure modes, verification order, and checkpoint requirements.
  - Define retry budget and stop conditions.
- Exit criteria:
  - Human approves plan checkpoint.
  - Acceptance criteria and verification commands are explicit.

### Implement
- Inputs:
  - Approved plan and scope budget.
- Activities:
  - Implement in bounded increments.
  - Keep core/shell/boundary separation strict.
  - Record rollback notes and deferred scope.
- Exit criteria:
  - Planned scope completed or deferrals documented.
  - Required tests added/updated.

### Verify
- Inputs:
  - Implementation summary, review findings, test report.
- Activities:
  - Run checks in deterministic order: type -> lint -> security -> property tests -> contract tests -> full suite.
  - Classify findings (blocking vs advisory).
  - Validate required approvals by risk tier.
- Exit criteria:
  - Go/no-go decision issued with residual risk and follow-ups.
  - Any blocking finding re-enters loop within retry cap.

### Loop Controls
- Retry budget:
  - Review-to-implement: max 2 loops.
  - Flake retry in test phase: max 3 reruns with triage notes.
- Trigger for re-plan:
  - Scope expansion, architecture deviation, or new high-risk finding.
- Trigger for hard stop:
  - Unresolved blocking issue after retry cap.
  - Missing mandatory human approval at required checkpoint.

## 5. Human-in-the-Loop Control Points
1. Plan approval gate:
   - Required before implementation begins.
   - Approver confirms scope, risk tier, acceptance criteria, and rollback feasibility.
2. High-risk implementation gate:
   - Required only when risk tier is `high`.
   - Approver confirms threat model impact, sensitive-file handling, and verification sufficiency.
3. Release gate:
   - Required before marking `Go`.
   - Approver confirms all blocking checks passed and residual risks are accepted.

## 6. Implementation Backlog
| Priority | Item | Scope | Dependencies | Done When |
|---|---|---|---|---|
| P0 | Add `scripts/check-report-quality.sh` | Validate required sections and non-empty checkpoint/evidence fields in review/test/verify artifacts | Existing templates and scripts | Script fails when approvals/citations are missing; integrated in smoke run |
| P0 | Enforce checkpoint gate in verify step | Block `Go` if required approvals are blank for active risk tier | Verify template + rule policy | Verify run returns non-zero for missing approvals |
| P1 | Add security scan command adapter | Tool-detect security command (`npm`, `bun`, `pnpm`, `yarn`, fallback skip with reason) | Release and verification rule | Verify report includes deterministic security outcome |
| P1 | Add artifact non-empty checks | Ensure `docs/current-plan.md`, `docs/impl-summary.md`, `docs/review-report.md`, `docs/test-report.md`, `docs/verify-report.md` are populated in real runs | Smoke script | Smoke fails on empty artifacts |
| P2 | Add workflow KPI log format | Track retries, blockers, and approval latency for process improvement | Optional metrics path | Metrics file produced per cycle and trendable |

## 7. Validation and Acceptance Tests
- Wiring and cross-reference checks:
  - `bash scripts/validate-claude-config.sh` must pass.
- Verification sequence checks:
  - `bash scripts/smoke-bootstrap.sh` must report `failed=0`.
  - Verify report must record gates in declared order.
- Human-gate checks:
  - For `high` risk, missing checkpoint approval must block final `Go`.
  - For `low`/`medium` risk, plan and release approvals remain mandatory.
- Regression checks:
  - Re-run validation after each workflow policy/template update.
  - Ensure crossrefs remain valid when agents/skills/commands are added.

## 8. Assumptions and Open Questions
- Assumptions:
  - This repository remains a reusable workflow baseline (not an app runtime repository).
  - Risk tier can be assigned during planning with human override.
  - Agent teams remain disabled by default unless explicitly enabled.
- Open questions:
  - Should report-quality gating run as a hook, CI check, or both?
  - Should `No-Go` artifacts be allowed to merge into template branches for auditability?
  - What KPI thresholds should trigger workflow redesign (for example, repeated blocker categories)?
