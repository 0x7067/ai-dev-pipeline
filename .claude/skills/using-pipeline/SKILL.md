---
name: using-pipeline
description: Meta-skill describing how to engage the ai-dev-pipeline workflow proactively. Auto-loaded at session start.
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

## Intent → skill/command mapping

Match what the user actually says. When the user types one of these signals, invoke the matching pipeline entry-point as your **first action**, before any other tool call or reply.

| User intent / phrasing | Invoke |
|---|---|
| "plan", "design", "how should we…", "what's the approach for…" | `/plan` (or `requirement-analysis` skill) |
| "implement", "build", "add", "write the code for…" | `/plan` first (gate), then `/implement` |
| "bug", "failing test", "broken", "regression", "something's off", "not working" | `requirement-analysis` skill, then `/plan` |
| "review", "look at this", "is this OK", "check my code" | `code-review` skill (or `/review`) |
| "refactor", "clean up", "restructure", "extract", "rename" | `/refactor` |
| "ship", "release", "ready to merge", "verify", "is this done" | `/verify`, then `static-analysis` |
| "test", "coverage", "property test", "contract test" | `test-gen` skill (or `/test`) |
| "audit", "health check", "overall state of…" | `/audit` |
| "research", "investigate", "what does X do", high-risk/unfamiliar area | `research` skill |

When in doubt between two: process skills (requirement-analysis, research) come **before** implementation skills.

## Required gates

Per `.claude/rules/release-and-verification.md`:

- `/plan` is required before any non-trivial code change. "Trivial" = typo fixes, comment edits, single-line config tweaks. Everything else needs a plan.
- Risk tier `medium` or `high` requires explicit human approval before implementation finalizes.
- Release gate (`/verify`) is required before declaring a change "done".

## Anti-rationalization list

These are the thoughts that mean **STOP — you are skipping the pipeline**. Every one of them is forbidden as a reason to bypass a skill.

| Rationalization | Reality |
|---|---|
| "This is just a quick fix." | The pipeline classifies risk; you don't. Run `/plan`. |
| "I just need to read the file first." | Skills tell you HOW to read and what to look for. Invoke first. |
| "The user didn't ask for a plan." | `/plan` is required by repo policy regardless of phrasing. |
| "I'll plan in my head and skip `/plan`." | Plans are artifacts. In-head plans don't pass the gate. |
| "I already know the answer." | The pipeline isn't for you; it's for the verifiable record. |
| "This is too small for the workflow." | Small things grow. The cost of running the skill is near-zero. |
| "Let me explore first, then decide." | Exploration without a skill burns context. Invoke, then explore. |
| "The test is obviously broken, I'll just fix it." | Bug → `requirement-analysis` first. No exceptions. |
| "Refactor is just moving code." | `/refactor` has its own pre/post gates for a reason. |
| "It's only adding one line." | Then `/plan` will be one paragraph. Run it. |

## How to invoke

In Claude Code, use the `Skill` tool with the skill name (e.g. `code-review`, `requirement-analysis`). For workflow phases that have slash commands (`/plan`, `/implement`, `/review`, `/test`, `/verify`, `/refactor`, `/audit`, `/cycle`), invoke the corresponding skill of the same name. Never use `Read` to load `SKILL.md` files manually.

## Non-coding requests

If the user's message is clearly non-coding ("what's the weather", "what's 2+2"), no pipeline skill applies. Respond directly. The 1%-match rule is about *coding intent*, not paranoia.

## Priority

1. User's explicit instructions in CLAUDE.md or the current message — highest priority.
2. This meta-skill and the pipeline rules in `.claude/rules/` — override default model behavior.
3. Default Claude Code behavior — lowest priority.

If the user explicitly says "skip the plan" or "just edit the file", follow them — but say once, briefly, that you are bypassing the pipeline at their direction.
