---
description: Review existing code, a diff, or a PR — severity-first architecture, security, and correctness findings. Use standalone when you want a review without running the full ship pipeline.
---

You are the orchestrator for `/review`. Do NOT review yourself — delegate to the `reviewer` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

0. **Mint run-id and export environment.** Same protocol as `/ship` step 0:
   - Reuse `RUN_ID` if already set (validated through `${CLAUDE_PLUGIN_ROOT}/scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`; else `RUN_ID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/mint-run-id.sh")`.
   - Resolve `AIDP_PROJECT_ROOT` and `AIDP_ARTIFACTS_ROOT` via `source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project-root.sh"` then `AIDP_PROJECT_ROOT="$(aidp_resolve_project_root)"` and `AIDP_ARTIFACTS_ROOT="$(aidp_resolve_artifacts_root "$AIDP_PROJECT_ROOT")"`. Export both. Fail closed on resolution error.
   - `export RUN_ID` and `export RUN_DIR="${AIDP_ARTIFACTS_ROOT}/runs/${RUN_ID}"`.
   - Create `${RUN_DIR}` and update `${AIDP_ARTIFACTS_ROOT}/latest`, `${AIDP_ARTIFACTS_ROOT}/latest.txt`, `${AIDP_PROJECT_ROOT}/.claude/workflow-state/active` atomically (`tmp + mv`).
   - Run `RUNS_ROOT="${AIDP_ARTIFACTS_ROOT}/runs" ARTIFACTS_ROOT="${AIDP_ARTIFACTS_ROOT}" bash "${CLAUDE_PLUGIN_ROOT}/scripts/prune-runs.sh"` (no-op when `CI=true`).
   - Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

1. Capture phase start time and print to the user:
   ```sh
   _phase_t0=$SECONDS
   _phase_started_at="$(date -u +%FT%TZ)"
   printf '▶ reviewer starting (run=%s)\n' "$RUN_ID"
   ```

2. Invoke the `reviewer` subagent via the Task tool. Pass the user's request as input AND ensure `RUN_ID` and `RUN_DIR` are present in the subagent's environment so `${RUN_DIR}/review-report.md` resolves correctly. Wait for it to return.

3. The reviewer's response ends with a single line in the form
   `STATUS: <state> | blocking=<n> advisory=<n> | <summary> | report=<path>`
   Capture that line.

4. Compute elapsed seconds, derive the phase outcome from the STATUS
   line, and print ONE line with the per-phase annotation `(Ns)`:
   ```sh
   _phase_secs=$(( SECONDS - _phase_t0 ))
   case "$STATUS_LINE" in
     "STATUS: ok"*) reviewer_ok=1 ;;
     *)             reviewer_ok=0 ;;
   esac
   ```
   - If `reviewer_ok=1` → `✓ reviewer ok (${_phase_secs}s) — <everything after "STATUS: ">`
   - Otherwise        → `✗ reviewer failed (${_phase_secs}s) — <everything after "STATUS: ">`

   Then append the timing record (additive; failure logged but never
   blocks the run):
   ```sh
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/append-phase-timing.sh" \
     --run-dir "$RUN_DIR" --name reviewer \
     --status "$([ "$reviewer_ok" = 1 ] && echo ok || echo fail)" \
     --seconds "$_phase_secs" --started-at "$_phase_started_at" \
     || printf '↷ phase-timing append skipped (rc=%d)\n' "$?"
   ```

5. Expected output is `${RUN_DIR}/review-report.md`. The reviewer runs the pragmatic-review-checklist second pass automatically for `medium`/`high` risk changes; do not invoke it from here.

   **A3 finding preview.** Immediately after the `✓|✗ reviewer — STATUS:…`
   echo, if `blocking>0` run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/preview-finding-titles.sh" "${RUN_DIR}/review-report.md" "## Blocking findings"`
   and print up to 3 indented title lines; else if `advisory>0`, run the
   helper with anchor `"## Advisory findings"`. Missing report or anchor →
   emit nothing (fail-closed). Preview lines never start with `STATUS:` (I2).

6. **End-of-run artifact summary.** As the very last output, invoke the
   shared renderer:

   ```sh
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/render-end-of-run.sh" --run-dir "$RUN_DIR" --run-id "$RUN_ID"
   ```

   The renderer reads `${RUN_DIR}/phase_timings.json` (via the boundary
   parser `${CLAUDE_PLUGIN_ROOT}/scripts/parse-phase-timings.sh` — never raw `jq`/`cat`),
   `${RUN_DIR}/decisions.jsonl`, and the optional
   `${RUN_DIR}/.failure-summary` to produce the canonical block in
   order: failures → timings → decisions → Artifacts. Artifact paths
   become OSC-8 hyperlinks on TTYs with `STYLE_COLOR=1`; `NO_COLOR=1`
   or non-TTY output suppresses all escapes. Same block shared verbatim
   across `/ship`, `/review`, `/refactor`, `/audit`, `/research`.
   Contract: `${CLAUDE_PLUGIN_ROOT}/docs/templates/end-of-run-summary-template.md`.
