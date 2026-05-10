# Current Plan Template

<!--
Risk-scaled rendering: this single template covers all risk tiers. Sections
marked Optional below are **omitted for `risk=low`** runs to keep the plan
within the risk-low ≤30-line cap (risk-low canonical shape — about 30 lines
or fewer; the 30-line cap is the canonical contract). For `risk=medium`/`risk=high`,
all sections are required.
-->

## Goal

## Scope

## Touched Files

<!-- Optional: omit for risk=low. Keep this section terse for risk=low; the
risk=low canonical shape is capped at ≤30 lines. -->

## Non-Goals
<!-- Optional: omit for risk=low. Risk=low plans skip the Non-Goals enumeration. -->

## Out-of-Scope
<!-- Optional: omit for risk=low. -->

## Evidence
- Official sources:
- External sources (max 2):

## Risk Profile
- Risk tier: `low` | `medium` | `high`
- Why this risk tier applies:
- change-type: <!-- optional: feature | fix | refactor | config. Used for
  reader context only; specs are optional and checked only when present. -->


## Human Checkpoints
1. Plan approval required before implementation:
2. Additional approval required for medium/high-risk changes:

## Approval Record
- Plan approval approver:
- Plan approval date:
- Plan approval evidence link:

## FC/IS Classification
<!-- Optional: omit for risk=low. -->
- Core:
- Shell:
- Boundary:

## Boundary Parsers
<!-- Optional: omit for risk=low. -->

## Invariants
<!-- Optional: omit for risk=low. -->

## Failure Modes
<!-- Optional: omit for risk=low. (Also called "Failure Modes and Mitigations"
in higher-risk plans.) -->

## Acceptance Criteria

## Norms applied
<!-- Optional: omit for risk=low. List the .claude/rules/*.md files this plan
adheres to. LINKS ONLY — do not paraphrase rule prose. Each bullet MUST be a
rule-file path under `.claude/rules/`. Rationale: paraphrasing drifts; links
do not. Enforced by scripts/validate-claude-config.sh (rule: a Norms applied
or Safeguards applied section must contain only `.claude/rules/<name>.md`
path references). -->

## Safeguards applied
<!-- Optional: omit for risk=low. Same shape as "Norms applied": list
`.claude/rules/<name>.md` paths only — no quoting, no paraphrase. Use this
section when the plan deliberately invokes a safeguard rule (e.g.
boundary-parse-dont-validate, security-baseline) to make the reliance
auditable. -->

## Open Decisions (provisional)
<!-- OPTIONAL — include only when the planner deferred non-load-bearing
choices for batched resolution at the plan-approval gate, per
.claude/rules/decision-surfacing.md. Each entry MUST list: the decision
name, the provisional pick, and a short rationale. The plan-gate
AskUserQuestion batch resolves every entry before approval; resolved
answers are recorded to ${RUN_DIR}/decisions.jsonl. Omit this section
if there are no provisional decisions. -->

## Verification Commands (Deterministic Order)
1. Type/compile:
2. Lint:
3. Security:
4. Property tests:
5. Contract tests:
6. Full suite:
