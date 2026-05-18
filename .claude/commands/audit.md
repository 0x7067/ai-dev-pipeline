---
description: Holistic project audit — structure, conventions, critical issues, quick wins, and design philosophy. Pass `standards` (or `standards --bucket <name>`) to run pattern discovery.
---

You are the orchestrator for `/audit`. Do NOT audit yourself — delegate to the `auditor` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

## Subcommand routing

If the user's input starts with `standards` (e.g. `/audit standards` or `/audit standards --bucket tests`):
- Parse any flags: `--bucket <name>`, `--threshold <n>`, `--min-bucket <n>`, `--langs <list>`.
- Run the `audit-standards` skill via `Skill("audit-standards")`, passing the parsed flags.
- Skip the `auditor` subagent steps below.
- The `audit-standards` skill handles its own RUN_ID minting and artifact writing.
- Return after the skill completes.

Otherwise (no subcommand, or unknown subcommand) → continue with the full auditor pipeline below.

Steps:

0. **Mint run-id and export environment.** Same protocol as `/ship` step 0:
   - Reuse `RUN_ID` if already set (validated through `${CLAUDE_PLUGIN_ROOT}/scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`; else `RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`.
   - Resolve `AIDP_PROJECT_ROOT` and `AIDP_ARTIFACTS_ROOT` via `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project-root.sh"` then `AIDP_PROJECT_ROOT="$(aidp_resolve_project_root)"` and `AIDP_ARTIFACTS_ROOT="$(aidp_resolve_artifacts_root "$AIDP_PROJECT_ROOT")"`. Export both. Fail closed on resolution error.
   - `export RUN_ID` and `export RUN_DIR="${AIDP_ARTIFACTS_ROOT}/runs/${RUN_ID}"`.
   - Create `${RUN_DIR}` and update `${AIDP_ARTIFACTS_ROOT}/latest`, `${AIDP_ARTIFACTS_ROOT}/latest.txt`, `${AIDP_PROJECT_ROOT}/.claude/workflow-state/active` atomically (`tmp + mv`).
   - Run `RUNS_ROOT="${AIDP_ARTIFACTS_ROOT}/runs" ARTIFACTS_ROOT="${AIDP_ARTIFACTS_ROOT}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/prune-runs.sh"` (no-op when `CI=true`).
   - Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

1. Print to the user:
   `▶ auditor starting (run=$RUN_ID)`

2. Invoke the `auditor` subagent via the Task tool. Pass the user's request as input AND ensure `RUN_ID` and `RUN_DIR` are present in the subagent's environment so `${RUN_DIR}/audit-report.md` resolves correctly. Wait for it to return.

3. The auditor's response ends with a single line in the form
   `STATUS: <state> | critical=<n> high=<n> medium=<n> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ auditor — <everything after "STATUS: ">`
   - Otherwise → `✗ auditor — <everything after "STATUS: ">`

5. Expected output is `${RUN_DIR}/audit-report.md`.

   **A3 finding preview.** Immediately after the `✓|✗ auditor — STATUS:…`
   echo, if `critical>0` run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview-finding-titles.sh" "${RUN_DIR}/audit-report.md" "## Critical or Urgent Issues"`
   and print up to 3 indented title lines; else if `high>0`, run the helper
   with anchor `"## Improvement Suggestions"`. Missing report or anchor → emit
   nothing (fail-closed). Preview lines never start with `STATUS:` (I2).

6. **End-of-run artifact summary.** As the very last output, render the
   end-of-run artifact summary block per
   `${CLAUDE_PLUGIN_ROOT}/docs/templates/end-of-run-summary-template.md`. Use absolute paths and
   only list artifacts that exist on disk. The same block is shared verbatim
   across `/ship`, `/review`, `/refactor`, `/audit`, `/research`.
