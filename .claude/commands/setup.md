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

2. **Rules** (`.claude/rules/`):
   - `code-style.md`
   - `architecture-fcis.md`
   - `boundary-parse-dont-validate.md`
   - `testing-formal-lite.md`
   - `security-baseline.md`
   - `release-and-verification.md`

3. **Report templates** (`docs/templates/`):
   - All `.md` files from the plugin's `docs/templates/` directory.

4. **CI workflow** (`.github/workflows/smoke.yml`).

5. **CLAUDE.md** at project root with `@`-references to the rules above. If a CLAUDE.md already exists, ask the user whether to merge or skip.

6. **`.gitignore` additions** — append these lines if not already present:
   ```
   docs/test-report.md
   docs/verify-report.md
   docs/review-report.md
   docs/current-plan.md
   docs/research/
   docs/review/
   ```

After scaffolding, print a summary of what was copied, what was skipped, and remind the user to review and commit the new files.
