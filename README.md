# ai-dev-pipeline

A reusable Claude Code workflow plugin for structured AI-assisted development. Enforces Functional Core / Imperative Shell (FC/IS) architecture, strict boundary parsing, and human approval checkpoints.

## Installation

**Install from the marketplace. That's it.** As of v0.4.0, every command, agent, skill, hook, and template resolves directly from the plugin install. No scaffolding step. Run `/ship` immediately.

> **Want CI to run the gates?** Invoke the `setup` skill once. CI runners do not load Claude Code plugins, so the canonical gate runner (`scripts/run-verification-gates.sh`) and its dependencies must be vendored into your repo for CI authority per `.claude/rules/release-and-verification.md`. The `setup` skill is the explicit "vendor for CI" operation; it is opt-in and not required for interactive use.

After vendoring (only if you ran the `setup` skill), verify the scaffolding:

```sh
bash scripts/validate-claude-config.sh   # confirms settings.json + cross-refs + boundary + version-sync
bash scripts/smoke-bootstrap.sh          # confirms required files and hook executability
```

Vendored copies always take precedence over plugin-shipped copies, so edits to vendored artifacts persist across plugin upgrades.

## Commands

The slash-command picker exposes exactly five primary entries:

| Command | Description |
|---|---|
| `/ship` | Run the full per-change pipeline (research → plan → implement → review → test → verify → smoke → release) with risk-adaptive approval gates by default. Pass `/ship strict` for unconditional plan approval. Replaces the previous `/cycle` and `/autopilot`. |
| `/review` | Review existing code, a diff, or a PR — severity-first architecture, security, and correctness findings (standalone, no full pipeline). |
| `/refactor` | Behavior-preserving structural change with pre/post verification gates and human approval. |
| `/audit` | Holistic project audit — structure, conventions, critical issues, and quick wins. |
| `/research` | Brainstorm, investigate, or get unstuck before any plan exists. |

> Other phase logic remains reachable via skills (no slash). The `setup` and `reset` operations are now skill-only (`setup`, `reset`); per-phase work (`requirement-analysis`, `test-gen`, `static-analysis`, etc.) is invoked by the corresponding skill rather than a dedicated slash command. See `.claude/skills/using-pipeline/SKILL.md`.

`/review` is a **merge gate** — operates on code changes, produces blocking/warning/advisory findings. `/audit` is a **project health check** — reviews the whole project periodically or before major architectural decisions.

## Workflow

`/ship` orchestrates the full per-change pipeline (research → plan → implement → review → test → verify → smoke → release). Default `adaptive` mode is risk-conditional with optional research and approval gates; `/ship strict` makes the plan-approval gate unconditional. Individual phase agents (`planner`, `implementer`, `tester`, `verifier`) are dispatched by name from `/ship` and are no longer exposed as standalone slash commands.

## Multi-Language Support

Examples are provided for four languages, each demonstrating FC/IS layers, boundary parsing, error handling, property-based tests, contract tests, end-to-end scenarios, and anti-patterns:

| Language | Directory |
|---|---|
| Python | `examples/python/` |
| Go | `examples/go/` |
| Rust | `examples/rust/` |
| TypeScript | `examples/typescript/` |

All examples are stdlib-only and self-contained. The boundary check script (`scripts/check-boundary-violations.sh`) auto-detects project language from markers (`pyproject.toml`, `go.mod`, `Cargo.toml`, `package.json`) and applies the appropriate ingress regex.

## Workflow Enforcement

Workflow phase prerequisites are enforced by hook-based gates on the underlying agents. The implementer phase is blocked before plan approval; reviewer and tester phases require an implementation; verifier requires test completion.

- State is tracked in `.claude/workflow-state.json` (gitignored)
- Invoke the `reset` skill to clear all phase completions and start a new task
- Set `WORKFLOW_GATES_SKIP=1` to bypass all checks
- `/ship` orchestrates internally and is not gated

## Proactive Invocation

Pipeline skills auto-engage based on intent — describing a bug, feature, review, refactor, or release triggers the matching skill before any other response. The `SessionStart` hook (`.claude/hooks/session-start.sh`) loads the `using-pipeline` meta-skill at session start, which carries the intent → skill mapping. The five primary slash commands (`/ship`, `/review`, `/refactor`, `/audit`, `/research`) remain available and behave identically when typed explicitly.

## Skills and Agents

Skills are auto-invoked by Claude based on their description. Agents are delegated to via the Task tool.

| Skill | Triggered by | Purpose |
|---|---|---|
| `requirement-analysis` | `planner` (under `/ship`) | FC/IS-aligned implementation specs |
| `fcis-architecture` | layer classification, design | Enforces core/shell/boundary separation |
| `code-review` | `/review`, post-implementation | FC/IS + security + correctness lenses on a diff |
| `static-analysis` | `verifier` (under `/ship`) | Language-detected verification gates |
| `test-gen` | `tester` (under `/ship`) | Property + contract tests |
| `refactor` | `/refactor` | Zero-behavior-change refactoring |
| `setup` | vendoring for CI gate authority | Scaffold scripts/templates/CI into the consuming repo (no slash command) |
| `reset` | clearing workflow state | Reset `.claude/workflow-state.json` (no slash command) |

Agents live under `.claude/agents/` (`planner`, `implementer`, `reviewer`, `tester`, `verifier`, `auditor`, `researcher`). Each has a `maxTurns` cap; if an agent stops mid-task, rerun the command or raise `maxTurns` in its frontmatter.

Add a custom skill at `.claude/skills/<name>/skill.md` with `name:` and `description:` frontmatter. The description determines when Claude invokes it — be specific, list trigger phrases, and add "do not invoke for X" guards. Validate with `bash scripts/validate-claude-config.sh`.

## CI / GitHub Actions

Three workflows ship in `.github/workflows/`:

| Workflow | Purpose |
|---|---|
| `claude.yml` | Responds to `@claude` mentions in issues and PRs to perform on-demand tasks |
| `claude-code-review.yml` | Automated Claude code review on opened/updated pull requests |
| `shellcheck.yml` | Runs ShellCheck across the repo on pull requests and pushes to `main` |

## Environment Variables

See [docs/env-vars.md](docs/env-vars.md) for the full reference. Notable knobs:

- `HOOKS_FAST=1` — opt into change-scoped fast-path hooks (defaults to `0`, full-run, in `run-verification-gates.sh`).
- `WORKFLOW_GATES_SKIP=1` — bypass workflow-state gating entirely.
- `VERIFY_TYPECHECK_CMD`, `VERIFY_LINT_CMD`, `VERIFY_SECURITY_CMD`, `VERIFY_PROPERTY_CMD`, `VERIFY_CONTRACT_CMD`, `VERIFY_FULL_CMD` — override gate commands per project.
- `VERIFY_REQUIRE_PROPERTY=1`, `VERIFY_REQUIRE_CONTRACT=1`, `VERIFY_REQUIRE_FULL_SUITE=1` — make optional test discovery failures blocking in strict CI.
- `HARNESS_JS_PACKAGE_MANAGER=pnpm` — force a JavaScript package manager when auto-detection is not enough.

See [docs/harness-engineering.md](docs/harness-engineering.md) for the harness portability notes and source references behind these defaults.
