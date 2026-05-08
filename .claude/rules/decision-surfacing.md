# Decision-Surfacing Rule

## Objective
Stop the `planner` and `researcher` agents from silently picking defaults on
behalf of the user. Meaningful design choices must be surfaced through the
`AskUserQuestion` tool DURING planning/research — BEFORE the choice bakes into
`docs/current-plan.md` or `docs/research/<topic>.md`.

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
`docs/current-plan.md` (planner) or `docs/research/<topic>.md` (researcher).

A question asked AFTER a default is already in the plan is too late: the
plan now anchors the user toward the agent's pick. Surface the choice while
the plan is still being drafted.

If the user already supplied the decision in the triggering prompt, treat it
as resolved — do not re-ask.

## Handling ambiguous answers
If a user answers an `AskUserQuestion` invocation ambiguously:

- Re-ask with clarified options, OR
- Record the ambiguity as an explicit open question in the plan/research
  note.

Do not silently default.

## References
- `.claude/agents/planner.md`
- `.claude/agents/researcher.md`
- `.claude/rules/release-and-verification.md` (approval gates)
