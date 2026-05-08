---
description: "Ops: Vendor ai-dev-pipeline artifacts (scripts, templates, rules, CI) into the current repo. Opt-in; required only for CI gate authority."
context: fork
---

## When do I need this?

**You don't need to run `/setup` for interactive use.** As of v0.4.0, `ai-dev-pipeline` is a zero-setup install: every command, agent, skill, and template resolves directly from `${CLAUDE_PLUGIN_ROOT}` after marketplace install. `/plan`, `/implement`, `/review`, `/test`, `/verify`, `/refactor`, `/ship`, and `/audit` all work immediately, with no scaffolding step.

Run `/setup` only when one of the following applies:

1. **CI gate authority.** Per `.claude/rules/release-and-verification.md`, a change is "verified" only when `scripts/run-verification-gates.sh` exits 0 in CI on the merge commit. CI runners do not load Claude Code plugins, so the gate runner and its dependencies must be vendored into the consuming repo for CI to invoke them. If you want CI to run the canonical gates, vendor once with `/setup`.
2. **Pin a snapshot.** You want the rules, templates, or gate runner checked into version control so a plugin upgrade cannot silently change behavior. Vendored copies always take precedence over plugin-shipped copies.
3. **Edit-and-keep customization.** You intend to edit a rule or template and have those edits persist independently of the plugin.

If none of those apply, skip `/setup` and just use the commands.

---

Scaffold the ai-dev-pipeline project artifacts into the current working directory.

Copy the following from `${CLAUDE_PLUGIN_ROOT}` into the project, skipping any file that already exists unless the user explicitly confirms overwrite:

1. **Scripts** (`scripts/`):
   - `run-verification-gates.sh`
   - `smoke-bootstrap.sh`
   - `check-boundary-violations.sh`
   - `check-crossrefs.sh`
   - `check-report-quality.sh`
   - `check-workflow-artifacts.sh`
   - `security-scan.sh`
   - `validate-claude-config.sh`
   Mark all as executable (`chmod +x`).

1a. **Workflow hooks** (`.claude/hooks/`):
   - `workflow-gate.sh`
   - `workflow-state-update.sh`
   Mark as executable (`chmod +x`).

1b. **Workflow state** (`.claude/workflow-state.json`):
   - Create the initial workflow state file with all phases set to `false`.
   - Ensure `.claude/workflow-state.json` is in `.gitignore`.

2. **Rules** (`.claude/rules/`):
   - `code-style.md`
   - `architecture-fcis.md`
   - `boundary-parse-dont-validate.md`
   - `testing-formal-lite.md`
   - `security-baseline.md`
   - `release-and-verification.md`

3. **Report templates** (`docs/templates/`):
   - All `.md` files from the plugin's `docs/templates/` directory.

3a. **Verification artifacts** (`docs/verification/`):
   - `acceptance-checklist.md` — create with the heading `# Acceptance Checklist` and a single placeholder item `- [ ] All verification gates passed.`

4. **CI workflow** (`.github/workflows/smoke.yml`) — **optional, ask the user first**.
   Only scaffold this file if the user explicitly opts in. Many projects already have their own CI pipelines, and the smoke gate can be integrated into an existing workflow by adding `bash scripts/smoke-bootstrap.sh` as a step.

4a. **Authoritative verify workflow** (`.github/workflows/verify.yml`) — **optional, ask the user first**.
   Copy `${CLAUDE_PLUGIN_ROOT}/templates/ci/github-actions-verify.yml.template` to `.github/workflows/verify.yml`. This implements the authoritative gate from `.claude/rules/release-and-verification.md` (Gate Authority section). Skip if the consuming repo already runs `scripts/run-verification-gates.sh` in its existing CI.

5. **CLAUDE.md** at project root with `@`-references to the rules above. If a CLAUDE.md already exists, ask the user whether to merge or skip.

6. **`.gitignore` additions** — append these lines if not already present:
   ```
   # Generated docs (recreated by agents each run)
   docs/*
   !docs/templates/
   ```

After scaffolding, print a summary of what was copied, what was skipped, and remind the user to review and commit the new files. Note that vendored copies will now take precedence over plugin-shipped copies — edits to vendored artifacts persist across plugin upgrades, but stale vendored copies will not auto-update when the plugin upgrades.
