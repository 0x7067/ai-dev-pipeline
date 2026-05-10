# Decision-Surfacing Directive — Notes

## Definitions

- **Meaningful decision (MUST ask):** any choice with two or more
  defensible options where the outcome is observable in produced artifacts
  or downstream agent behavior. Includes:
  - Defaults (timeouts, retry counts, page sizes, log levels).
  - Names (feature names, file names exposed in plans, public symbol names).
  - Mechanism / library picks.
  - Scope trade-offs (in-scope vs follow-up; minimal vs comprehensive cut).
  - Naming conventions across files/symbols.
  - Mode or sub-command grammar (e.g., `/ship strict` vs `/ship --strict`).
  - Threshold values (coverage %, complexity caps, severity cutoffs).
  - Anything affecting consumer-visible API.
  - Any decision with multiple defensible options that the agent cannot
    eliminate on technical grounds alone.
- **Trivial decision (DON'T ask):** mechanics with no consumer-visible
  contract impact. Includes:
  - File paths internal to a module.
  - Command syntax choices (`sed` vs `perl` vs `awk`).
  - Tool selection for the same job (`jq` vs `python -c`).
  - Commit message wording.
  - Internal identifier names confined to a single function body.
- **Ambiguous → ask:** if the agent cannot confidently classify a
  decision as trivial, it MUST treat it as meaningful and ask. Bias
  toward the user.

## Required Agent Behavior

- When 2+ defensible options exist for a meaningful decision, the agent
  MUST invoke `AskUserQuestion` BEFORE writing the plan or research note
  that would otherwise default the decision.
- The agent's recommendation MUST be option #1 in the `AskUserQuestion`
  prompt, suffixed with the literal string `(Recommended)`.
- For decisions with one clearly correct answer, the agent picks
  autonomously and records a one-line rationale. No `AskUserQuestion`.
- The directive applies only to `planner` and `researcher` agents.

## Risks

- Over-asking that fatigues the user → mitigated by explicit trivial set.
- Under-asking via mis-classification → mitigated by ambiguous-→-ask
  clause and reviewer-visible rule text.
- Cache mirror drift → mitigated by explicit sync step.
