---
description: Review existing code, a diff, or a PR — severity-first architecture, security, and correctness findings. Use standalone when you want a review without running the full ship pipeline.
---

You are the orchestrator for `/review`. Do NOT review yourself — delegate to the `reviewer` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

0. **Mint run-id and export environment.** Same protocol as `/ship` step 0:
   - Reuse `RUN_ID` if already set (validated through `scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash scripts/mint-run-id.sh)`; else `RUN_ID=$(bash scripts/mint-run-id.sh)`.
   - `export RUN_ID` and `export RUN_DIR="docs/runs/${RUN_ID}"`.
   - Create `${RUN_DIR}` and update `docs/latest`, `docs/latest.txt`, `.claude/workflow-state/active` atomically (`tmp + mv`).
   - Run `bash scripts/prune-runs.sh` (no-op when `CI=true`).
   - Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

1. Print to the user:
   `▶ reviewer starting (run=$RUN_ID)`

2. Invoke the `reviewer` subagent via the Task tool. Pass the user's request as input AND ensure `RUN_ID` and `RUN_DIR` are present in the subagent's environment so `${RUN_DIR}/review-report.md` resolves correctly. Wait for it to return.

3. The reviewer's response ends with a single line in the form
   `STATUS: <state> | blocking=<n> advisory=<n> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ reviewer — <everything after "STATUS: ">`
   - Otherwise → `✗ reviewer — <everything after "STATUS: ">`

5. Expected output is `${RUN_DIR}/review-report.md`. The reviewer runs the pragmatic-review-checklist second pass automatically for `medium`/`high` risk changes; do not invoke it from here.
