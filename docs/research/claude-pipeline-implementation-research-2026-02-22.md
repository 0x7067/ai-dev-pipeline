# Claude Pipeline Research for Implementation

Date: 2026-02-22
Scope: Validate implementation-critical claims from `ai-dev-pipeline-report.md` and define a build plan for this repository.

## Similar implementations
- None found in this repo (greenfield): no existing `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.claude/rules/`, or `.claude/hooks/` content.
- Repo state note: this directory currently has no `.git`, so any deploy/versioning steps in the plan require either repository initialization or a different project root.

## Integration points
- Claude Code skills and command entrypoints: `.claude/skills/*/SKILL.md` and optional `.claude/commands/*.md`.
- Subagents: `.claude/agents/*.md`.
- Shared settings and hooks: `.claude/settings.json`.
- Team conventions/memory: `CLAUDE.md` and optional rule files.
- Optional experimental parallel coordination: agent teams via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Config and feature flags
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enables agent teams (experimental).
- Hook configuration should live in `.claude/settings.json` for project-shared behavior.
- Subagent scope priority: CLI `--agents` > project `.claude/agents/` > user `~/.claude/agents/` > plugins.

## Tests to mirror
- None in repo. We need to create deterministic validation scripts and CI checks for:
  - cross-reference integrity (commands -> agents, agents -> skills, CLAUDE.md -> rule files)
  - hooks JSON schema validity
  - basic smoke checks for skill and subagent frontmatter fields

## Evidence-checked findings

### Confirmed by official docs
1. Skills and custom slash commands share behavior; existing `.claude/commands/` still work, and skills are preferred for extra capabilities.
2. In skills, frontmatter fields are optional; `description` is recommended, not required.
3. In subagents, `name` and `description` are required; other fields are optional (`tools`, `model`, `maxTurns`, `skills`, `hooks`, etc.).
4. Hooks are configured in settings, support multiple events (`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStart`, `SubagentStop`, etc.), and can block/allow operations through structured output.
5. Agent teams are experimental and require explicit enablement.

### Not confirmed as hard facts (treat as heuristics/opinion)
1. "80% of value comes from planning and verification".
2. "~70% reduction in wrong-architecture suggestions from ~2,500-token CLAUDE.md".
3. "~100 startup tokens per skill" fixed budget estimate.
4. Specific version claim: "merged since v2.1".

## Implementation decisions for this repo
1. Start with **subagents + skills + hooks** (stable baseline).
2. Keep **agent teams disabled** initially; add later after baseline passes.
3. Convert all hard percentages in documentation to either:
   - sourced metrics with reproducible method, or
   - explicitly labeled internal heuristics.
4. Add one validation script as a quality gate before adding many artifacts.

## Proposed plan (implementation-ready)
1. Bootstrap structure and memory:
   - create `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, `.claude/rules/`, `.claude/hooks/`
   - create `CLAUDE.md` with minimal conventions and references
2. Implement orchestration path first:
   - `/plan`, `/implement`, `/review`, `/test`, `/verify`
   - 3 initial subagents: `planner`, `implementer`, `reviewer`
3. Add deterministic verification hooks:
   - `protect-files` (PreToolUse)
   - `type-check` + `lint-on-edit` (PostToolUse)
   - `format-on-stop` (Stop)
4. Add validation tooling:
   - script that verifies cross-references and required frontmatter for subagents
   - CI check to run validation on PRs
5. Extend to full cycle:
   - add deploy-prep and optional `/cycle`
   - add optional agent teams only after baseline metrics are stable

## Sources
- Skills docs: https://code.claude.com/docs/en/skills
- Subagents docs: https://code.claude.com/docs/en/sub-agents
- Hooks reference: https://code.claude.com/docs/en/hooks
- Settings docs: https://code.claude.com/docs/en/settings
- Agent teams docs: https://code.claude.com/docs/en/agent-teams
- Anthropic engineering index: https://www.anthropic.com/engineering
- Building effective agents (context for orchestration tradeoffs): https://www.anthropic.com/engineering/building-effective-agents
- Context engineering for coding agents: https://www.anthropic.com/engineering/claude-code-best-practices
