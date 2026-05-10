# ai-dev-pipeline

A Claude Code workflow plugin for structured AI-assisted development. It keeps the default path short: plan, implement, review, verify, smoke, release.

## Installation

Install from the marketplace and run `/ship`. No scaffolding step.

CI runners do not load Claude Code plugins, so to give CI gate authority (per `.claude/rules/release-and-verification.md`) invoke the `setup` skill once to vendor `scripts/run-verification-gates.sh` and friends into the repo. Then:

```sh
bash scripts/validate-claude-config.sh   # settings.json + cross-refs + boundary + version-sync
bash scripts/smoke-bootstrap.sh          # required files and hook executability
```

Vendored copies override plugin-shipped copies, so edits survive plugin upgrades.

## Commands

Five primary slash commands:

| Command | Purpose |
|---|---|
| `/ship` | Per-change pipeline: optional research → plan → implement → review → verify → smoke → release. Low-risk green runs auto-finish; `/ship strict` requires explicit approvals. |
| `/review` | Severity-first review of a diff, file, or PR. No pipeline. |
| `/refactor` | Behavior-preserving structural change with pre/post gates. |
| `/audit` | Project-wide health check. |
| `/research` | Brainstorm or scope before a plan exists. |

`/review` is a merge gate on a diff. `/audit` is a project-level health check. Other phase logic lives in skills (`requirement-analysis`, `test-gen`, `static-analysis`, `setup`, `reset`); see `.claude/skills/using-pipeline/SKILL.md`.

## Multi-Language Support

Examples for Python, Go, Rust, and TypeScript live under `examples/<lang>/`, each demonstrating FC/IS layers, boundary parsing, error handling, property and contract tests, and anti-patterns. Stdlib only.

`scripts/check-boundary-violations.sh` detects the project language from `pyproject.toml`, `go.mod`, `Cargo.toml`, or `package.json` and applies the matching ingress regex.

## Workflow Enforcement

Hook-based gates on agents enforce phase order: implementer is blocked before a plan, reviewer before implementation, verifier before review. `/ship` orchestrates internally and is not gated.

State lives in `.claude/workflow-state.json` (gitignored). Invoke the `reset` skill to start a new task. Set `WORKFLOW_GATES_SKIP=1` to bypass.

## Proactive Invocation

The `SessionStart` hook (`.claude/hooks/session-start.sh`) loads the `using-pipeline` meta-skill, which carries the intent → skill mapping. Describing a bug, feature, review, refactor, or release triggers the matching skill before any other response. Typed slash commands behave identically.

## Skills and Agents

| Skill | Used by | Purpose |
|---|---|---|
| `requirement-analysis` | `planner` | FC/IS-aligned implementation specs |
| `fcis-architecture` | layer classification | Core/shell/boundary separation |
| `code-review` | `/review` | FC/IS + security + correctness on a diff |
| `static-analysis` | `verifier` | Language-detected verification gates |
| `test-gen` | `tester` | Property + contract tests |
| `refactor` | `/refactor` | Zero-behavior-change refactoring |
| `setup` | CI gate authority | Vendor scripts/templates/CI |
| `reset` | new task | Clear `.claude/workflow-state.json` |

Agents under `.claude/agents/` (`planner`, `implementer`, `reviewer`, `tester`, `verifier`, `auditor`, `researcher`) each carry a `maxTurns` cap; rerun the command or raise the cap if an agent stops mid-task.

Add a custom skill at `.claude/skills/<name>/skill.md` with `name:` and `description:` frontmatter. The description controls when Claude invokes it — list trigger phrases and "do not invoke for X" guards. Validate with `bash scripts/validate-claude-config.sh`.

## CI

Three workflows in `.github/workflows/`:

| Workflow | Purpose |
|---|---|
| `claude.yml` | `@claude` mentions in issues and PRs |
| `claude-code-review.yml` | Automated review on opened/updated PRs |
| `shellcheck.yml` | ShellCheck on PRs and pushes to `main` |

## Run-ID Isolation

Every primary command mints a `RUN_ID` at step 0 and exports `RUN_ID` and `RUN_DIR` (= `docs/runs/<RUN_ID>`). Per-run artifacts — plans, specs, research notes, reports, gate logs, retry hints — write under `${RUN_DIR}/`. Concurrent runs (two `/ship` sessions, CI + local, two worktrees) are safe by construction.

Step 0 atomically maintains three discovery pointers: `docs/latest` (symlink), `docs/latest.txt` (text fallback), and `.claude/workflow-state/active`. Read-only verification gates (`typecheck`, `lint`, `security`) run in parallel inside `scripts/run-verification-gates.sh`; test gates remain sequential.

See [docs/specs/run-id-isolation/spec.yaml](docs/specs/run-id-isolation/spec.yaml) and [`.claude/skills/using-pipeline/SKILL.md`](.claude/skills/using-pipeline/SKILL.md).

## Environment Variables

Full reference in [docs/env-vars.md](docs/env-vars.md). Notable knobs:

- `RUN_ID`, `RUN_DIR` — active run-id and resolved directory; set by step 0.
- `RUN_RETENTION` — run dirs to keep under `docs/runs/` (default `10`); honored by `scripts/prune-runs.sh`. CI=true is a no-op.
- `REPORT_REVIEW_PATH`, `REPORT_TEST_PATH`, `REPORT_VERIFY_PATH` — overrides for `scripts/check-report-quality.sh`. Defaults resolve through `${RUN_DIR}/`, then `docs/latest/`, then legacy `docs/<report>.md`.
- `HOOKS_FAST=1` — change-scoped fast-path hooks (default `0`).
- `WORKFLOW_GATES_SKIP=1` — bypass workflow-state gating.
- `WORKFLOW_STATE_PATH` — explicit override for the workflow-state JSON.
- `VERIFY_TYPECHECK_CMD`, `VERIFY_LINT_CMD`, `VERIFY_SECURITY_CMD`, `VERIFY_PROPERTY_CMD`, `VERIFY_CONTRACT_CMD`, `VERIFY_FULL_CMD` — per-project gate command overrides.
- `VERIFY_REQUIRE_PROPERTY=1`, `VERIFY_REQUIRE_CONTRACT=1`, `VERIFY_REQUIRE_FULL_SUITE=1` — make optional test discovery failures blocking.
- `HARNESS_JS_PACKAGE_MANAGER=pnpm` — force a JS package manager when auto-detection falls short.

Portability notes and source references are in [docs/harness-engineering.md](docs/harness-engineering.md).

## Tuning

### Verifier Retry Hint

`scripts/run-verification-gates.sh` supports one bounded retry by default:

- `MAX_VERIFY_RETRIES` (default `1`) — retries per gate after a non-zero exit. Set `0` in CI when immediate failure is preferred.
- `VERIFY_RETRY_HINT_FILE` — single-line JSON hint (`{"gate":"<label>","exit_code":<n>,"attempt":<n>}`) written on every failure for the next pass. Defaults to `${RUN_DIR}/.verify-retry.json`, or `docs/.verify-retry.json` when no run is active.

```sh
MAX_VERIFY_RETRIES=1 bash scripts/run-verification-gates.sh
# on failure: cat "${RUN_DIR}/.verify-retry.json"
# → {"gate":"lint","exit_code":1,"attempt":0}
```

Authoritative semantics: `.claude/rules/release-and-verification.md` under "Canonical Gate Runner".
