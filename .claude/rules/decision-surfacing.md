# Decision-Surfacing Rule

## Objective
Stop the `planner` and `researcher` agents from silently picking defaults on
behalf of the user. Meaningful design choices must be surfaced through the
`AskUserQuestion` tool DURING planning/research — BEFORE the choice bakes into
`${RUN_DIR}/current-plan.md` or `${RUN_DIR}/research/<topic>.md`.

## Scope
Applies to:
- `.claude/agents/planner.md`
- `.claude/agents/researcher.md`

Other agents (`implementer`, `reviewer`, `tester`, `verifier`, `auditor`) are
unaffected. They consume already-resolved decisions.

## Meaningful (must ask)
Surface via `AskUserQuestion` whenever the run encounters any of:

- **Defaults** the user will inherit (timeouts, retry counts, log levels,
  feature-flag default state).
- **Names** that surface anywhere user-visible: file names, command names,
  flag names, environment variable names, public function/symbol names,
  artifact paths.
- **Mechanism / library picks** when more than one defensible option exists
  (HTTP client choice, parser library, test runner, lint tool, storage
  backend).
- **Scope trade-offs** (do we include feature X now or defer; do we touch
  module Y or stub it).
- **Naming conventions** introduced or extended (kebab vs snake, prefix
  scheme, version scheme).
- **Mode grammar** for CLIs/agents (subcommand shape, modifier keywords,
  argument order).
- **Threshold values** (limits, sizes, percentages, retry caps, rate limits).
- **Anything affecting consumer-visible API** (signatures, return shapes,
  error codes, exit codes, HTTP status mapping).
- **Anything with multiple defensible options** where reasonable engineers
  would disagree.

## Trivial (don't ask)
Decide autonomously and record inline without a rationale block:

- **File paths** internal to the implementation (where to put a helper).
- **Command syntax** choices (`sed` vs `perl`, `awk` vs `cut`).
- **Tool selection for one-off mechanics** (`jq` vs `python -c` for JSON
  extraction in a script).
- **Commit message wording** (subject line phrasing, body prose).
- **Internal identifier naming inside a single function body** (loop
  variables, intermediate locals).

## Ambiguous → ask
If the agent cannot confidently classify a decision as trivial, treat it as
meaningful and ask. Fail-open toward the user, not the agent. The cost of an
extra question is small; the cost of a silently baked default the user
disagrees with is rework.

## (Recommended) option-#1 convention
When `AskUserQuestion` is invoked:

- The agent's recommended option is option #1.
- The label of option #1 ends with the literal suffix `(Recommended)`.
- Other defensible options follow as #2, #3, … without the suffix.
- A free-text "Other" option is included where the tool supports it, so the
  user is never trapped inside the agent's option set.

## Timing requirement
Ask DURING planning/research, BEFORE the chosen value is written into
`${RUN_DIR}/current-plan.md` (planner) or `${RUN_DIR}/research/<topic>.md` (researcher).

A question asked AFTER a default is already in the plan is too late: the
plan now anchors the user toward the agent's pick. Surface the choice while
the plan is still being drafted.

If the user already supplied the decision in the triggering prompt, treat it
as resolved — do not re-ask.

## Draft plan with open decisions (batch at plan gate)
The "ask BEFORE writing" rule above is preserved for **single, load-bearing**
decisions: when one specific choice gates the rest of the plan, ask before
drafting. For plans that touch many small decisions, the planner MAY:

1. Draft the plan with each meaningful-but-not-load-bearing choice marked
   `(provisional — to be confirmed at plan gate)` in an "Open Decisions"
   section, AND
2. Surface ALL provisional decisions in a single `AskUserQuestion` batch at
   the plan-approval gate, BEFORE the user replies `approve|edit|reject`.

This is a batching optimization, not a relaxation. Anti-fatigue rationale:
ten well-framed questions answered once beat ten halts strung across an
hour. The planner MUST NOT silently bake provisional defaults; the
"Open Decisions" section is the visible audit trail and MUST list every
provisional pick. After the user answers, the planner re-emits the plan
with the resolved values and records each answered decision in
`${RUN_DIR}/decisions.jsonl` per
`docs/templates/decisions-jsonl-schema.md`.

The orchestrator policy (auto vs strict, risk tier → halt behavior) is
sourced from `.claude/policy/approvals.yaml`, parsed via
`scripts/parse-approvals-policy.sh` — the planner does not re-derive it.

## Handling ambiguous answers
If a user answers an `AskUserQuestion` invocation ambiguously:

- Re-ask with clarified options, OR
- Record the ambiguity as an explicit open question in the plan/research
  note.

Do not silently default.

## Open-Decisions ⇔ AskUserQuestion pairing (mandatory)

Any agent file under `.claude/agents/*.md` that contains an "Open
Decisions" section (literal Markdown heading, any case, optional trailing
parenthetical such as `(provisional)`) MUST also contain an explicit
`AskUserQuestion` instruction. The pairing is enforced by
`scripts/validate-claude-config.sh`:

- An "Open Decisions" heading without `AskUserQuestion` anywhere in the
  same file is a hard error — the validator exits non-zero with the
  offending file path.
- The validator is pure-bash (no extra dependency) and runs as part of
  the standard CI gate.

## Approval halts use AskUserQuestion (not prose)

Approval halts in `.claude/commands/*.md` (plan gate, release gate, any
analogous gate) MUST be expressed as an `AskUserQuestion` invocation, not
as a prose `reply "approve" / "edit <comment>" / "reject"` instruction.
The orchestrator command file MUST contain an `AskUserQuestion` block in
the same section as the halt.

- Plan gate: option #1 `Approve (Recommended)`; option #2 `Reject`. The
  free-text "Other" entry is interpreted as `edit <comment>` (the
  comment is the user's free text). Each option's `description` should
  state the consequence in plain language — no fixed prefix required.
- Release gate: option #1 `Approve (Recommended)`; option #2 `Reject`.
  No `edit` option (HITL plan invariant 8).

The validator flags any `.claude/commands/*.md` containing the literal
prose pattern `reply "approve"` or `reply "reject"` without a paired
`AskUserQuestion` block in the same section.

## References
- `.claude/agents/planner.md`
- `.claude/agents/researcher.md`
- `.claude/rules/release-and-verification.md` (approval gates)
- `scripts/validate-claude-config.sh` (enforces the Open-Decisions pairing rule)
