---
description: Scaffold project-level artifacts (scripts, templates, rules, CI) into the current repo.
context: fork
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

5. **CLAUDE.md** at project root with `@`-references to the rules above. If a CLAUDE.md already exists, ask the user whether to merge or skip.

6. **`.gitignore` additions** — append these lines if not already present:
   ```
   # Generated docs (recreated by agents each run)
   docs/*
   !docs/templates/
   ```

After scaffolding, print a summary of what was copied, what was skipped, and remind the user to review and commit the new files.
