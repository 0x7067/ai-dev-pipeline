---
description: Brainstorm, investigate, or get unstuck before any plan exists. Use standalone for open-ended exploration, library/API research, or scoping unclear work.
---

You are the orchestrator for `/research`. Do NOT research yourself — delegate to the `researcher` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

Steps:

0. **Mint run-id and export environment.** Same protocol as `/ship` step 0:
   - Reuse `RUN_ID` if already set (validated through `scripts/parse-run-id.sh`); else if `GITHUB_RUN_ID` is set, mint via `RUN_ID=$(GITHUB_RUN_ID="$GITHUB_RUN_ID" bash scripts/mint-run-id.sh)`; else `RUN_ID=$(bash scripts/mint-run-id.sh)`.
   - `export RUN_ID` and `export RUN_DIR="docs/runs/${RUN_ID}"`.
   - Create `${RUN_DIR}/research/` and update `docs/latest`, `docs/latest.txt`, `.claude/workflow-state/active` atomically (`tmp + mv`).
   - Run `bash scripts/prune-runs.sh` (no-op when `CI=true`).
   - Print `▶ run minted RUN_ID=$RUN_ID RUN_DIR=$RUN_DIR`.

1. Print to the user:
   `▶ researcher starting (run=$RUN_ID)`

2. Invoke the `researcher` subagent via the Task tool. Pass the user's request as input AND ensure `RUN_ID` and `RUN_DIR` are present in the subagent's environment so `${RUN_DIR}/research/<topic>.md` resolves correctly. Wait for it to return.
   - **Story-shaped topics auto-trigger INVEST decomposition.** The
     researcher applies the conservative heuristic documented in
     `.claude/agents/researcher.md` (`<invest-mode>`): topics containing
     `as a <role>`, both `i want` and `so that`, or an explicit
     acceptance-criteria / given-when-then block produce an additional
     "INVEST Decomposition" section in the research note. Non-story
     topics produce output byte-identical to today (invariant I4). No
     modifier or env-var gates this — detection is always-on.

3. The researcher's response ends with a single line in the form
   `STATUS: <state> | <summary> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: ok` → `✓ researcher — <everything after "STATUS: ">`
   - Otherwise → `✗ researcher — <everything after "STATUS: ">`

5. Expected output is `${RUN_DIR}/research/<topic>.md`.

6. **End-of-run artifact summary.** As the very last output, render the
   end-of-run artifact summary block per
   `docs/templates/end-of-run-summary-template.md`. Use absolute paths and
   only list artifacts that exist on disk. The same block is shared verbatim
   across `/ship`, `/review`, `/refactor`, `/audit`, `/research`.
