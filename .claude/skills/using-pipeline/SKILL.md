---
name: using-pipeline
description: Use when deciding which ai-dev-pipeline command, skill, or agent should handle a coding intent; auto-loaded at session start and maps user requests to proactive workflow entry points.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance that an ai-dev-pipeline skill, command, or agent applies to what the user is asking, you ABSOLUTELY MUST invoke it via the `Skill` tool BEFORE producing any other response — including clarifying questions, exploration, or "let me just read the file first."

IF A PIPELINE SKILL APPLIES, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

## Why this exists

`ai-dev-pipeline` enforces a deterministic Functional Core / Imperative Shell workflow with explicit human approval gates (see `.claude/rules/release-and-verification.md`). Skipping the pipeline — by jumping straight to edits, "quick fixes", or ad-hoc reasoning — bypasses risk-tier classification, parse-at-boundary enforcement, and the gate runner. The whole point of this repo is that those gates run.

## Intent → command mapping

Match what the user actually says. When the user types one of these signals, invoke the matching pipeline entry-point as your **first action**, before any other tool call or reply.

The primary user-facing surface is exactly five slash commands:

| User intent / phrasing | Invoke |
|---|---|
| Any code change: "implement", "build", "add", "fix", "ship", "release", "ready to merge", "verify", "is this done", bug reports, failing tests | `/ship` (default `auto`; pass `strict` to force explicit approvals) |
| "review this", "look at this diff/PR", severity-first review of existing code without running the full pipeline | `/review` |
| "refactor", "clean up", "restructure", "extract", "rename", "split this up", "tidy" | `/refactor` |
| "audit", "health check", "overall state of…", project-wide review with no code change | `/audit` |
| "research", "brainstorm", "investigate", "I'm stuck", "explore options before planning", library/API scoping | `/research` |

> **Zero-setup default**: as of v0.4.0, the pipeline works directly from the marketplace install with no scaffolding step. The `setup` skill is opt-in and primarily exists to satisfy CI gate authority (CI does not load Claude Code plugins). Do not suggest `setup` as a precondition for interactive commands.

> **Skills (no slash)**: per-phase logic that previously had its own slash command is now reachable only via skills. Invoke by skill name through the `Skill` tool: `setup` (vendor artifacts for CI), `reset` (clear `.claude/workflow-state.json`), `requirement-analysis` (planning specs, used by `planner`), `code-review` (used by `reviewer`), `test-gen` (used by `tester`), `static-analysis` (used by `verifier`), `research` (used by `researcher`), `fcis-architecture`, `pragmatic-review-checklist`. The corresponding agents (`planner`, `implementer`, `tester`, `verifier`, `researcher`) are dispatched by `/ship` by name; you do not need to invoke them directly.

When in doubt between two: process skills (requirement-analysis, research) come **before** implementation skills, but for any user-visible action prefer the command surface above.

### Agent-internal reference skills

The following skills are reference/process material that the pipeline agents invoke internally; users should not need to call them directly:

- `requirement-analysis` — used by `planner`
- `fcis-architecture` — used by `planner` and `reviewer`
- `code-review` — used by `reviewer`
- `pragmatic-review-checklist` — used by `reviewer` (advisory second pass on medium/high risk)
- `static-analysis` — used by `verifier`
- `test-gen` — used by `tester`
- `refactor` — used by `/refactor`
- `research` — used by `researcher`

## Run-ID isolation contract

Every primary command (`/ship`, `/audit`, `/review`, `/research`,
`/refactor`) mints a `RUN_ID` at step 0 and exports `RUN_ID` and
`RUN_DIR` (= `docs/runs/<RUN_ID>`) into the environment of every
subagent it dispatches. All per-run artifacts — plans, specs,
research notes, review/test/verify reports, refactor
reports, gate logs, retry hints — are written under `${RUN_DIR}/`.

This makes concurrent runs (two `/ship` sessions on the same repo, CI
+ local, two worktrees) safe by construction: each run has its own
artifact tree.

Discovery is done through three pointers, all maintained atomically
by the orchestrator's step 0:

- `docs/latest` — symlink to the active run's directory.
- `docs/latest.txt` — text fallback containing the active run-id.
- `.claude/workflow-state/active` — text file containing the active
  run-id; consumed by hooks that need to find the per-run
  workflow-state file.

Resolution order at the consumer side: `RUN_ID` env →
`.claude/workflow-state/active` → `docs/latest` → `docs/latest.txt`.
All four go through `scripts/parse-run-id.sh` before any path is
constructed (parse, don't validate). See
`docs/specs/run-id-isolation.md` for the full spec.

### Upstream phases are sequential by data dependency

The `/ship` pipeline fans out only the *read-only* verification gates
(typecheck, lint, security) inside `scripts/run-verification-gates.sh`.
The upstream phases — optional `research` → `plan` → `implement` →
`review` — remain sequential because each phase consumes the prior phase's
artifact:

- `plan` reads `${RUN_DIR}/research/<topic>.md` (when present).
- `implement` reads `${RUN_DIR}/current-plan.md`.
- `review` reads the `## Implementation` section of `${RUN_DIR}/current-plan.md` plus the diff (the standalone impl-summary.md was folded into current-plan.md on 2026-05).

Parallelizing any of these would force a phase to read an artifact
its upstream has not yet produced. Do not attempt it without first
breaking the data dependency.

## Required gates

Per `.claude/rules/release-and-verification.md`:

- A plan (produced by the `planner` agent under `/ship`) is required before implementation.
- Risk tier `medium` or `high` requires explicit human approval before implementation.
- Release gate (the `verifier` agent under `/ship`, or the `static-analysis` skill standalone) is required before declaring a change "done".

## Anti-rationalization list

These are the thoughts that mean **STOP — you are skipping the pipeline**. Every one of them is forbidden as a reason to bypass a skill.

| Rationalization | Reality |
|---|---|
| "This is just a quick fix." | The pipeline classifies risk; you don't. Run `/ship`. |
| "I just need to read the file first." | Skills tell you HOW to read and what to look for. Invoke first. |
| "The user didn't ask for a plan." | A plan is required by repo policy regardless of phrasing — `/ship` produces one via `planner`. |
| "I'll plan in my head and skip the plan step." | Plans are artifacts. In-head plans don't pass the gate. |
| "I already know the answer." | The pipeline isn't for you; it's for the verifiable record. |
| "This is too small for the workflow." | Small things grow. The cost of running the skill is near-zero. |
| "Let me explore first, then decide." | Exploration without a skill burns context. Invoke, then explore. |
| "The test is obviously broken, I'll just fix it." | Bug → `requirement-analysis` first. No exceptions. |
| "Refactor is just moving code." | `/refactor` has its own pre/post gates for a reason. |
| "It's only adding one line." | Then the plan will be one paragraph. Run `/ship`. |

## How to invoke

- **User typed a slash command** (`/ship`, `/review`, `/refactor`, `/audit`, `/research`): the harness already dispatches it. Do not narrate or attempt to re-invoke via the `Skill` tool — just let it run.
- **User expressed an intent without a slash command**: invoke the matching skill via the `Skill` tool (e.g. `code-review`, `requirement-analysis`, `setup`, `reset`). For the five primary slash commands, the skill listing exposes them under the same name (`audit`, `refactor`, `research`, …) — invoke that skill name directly.

Never use `Read` to load `SKILL.md` files manually.

## Non-coding requests

If the user's message is clearly non-coding ("what's the weather", "what's 2+2"), no pipeline skill applies. Respond directly. The 1%-match rule is about *coding intent*, not paranoia.

## Priority

1. User's explicit instructions in CLAUDE.md or the current message — highest priority.
2. This meta-skill and the pipeline rules in `.claude/rules/` — override default model behavior.
3. Default Claude Code behavior — lowest priority.

If the user explicitly says "skip the plan" or "just edit the file", follow them — but say once, briefly, that you are bypassing the pipeline at their direction.
