---
description: Advanced — Run verification gates and produce go/no-go decision. Prefer `/ship` for the full flow.
---

You are the orchestrator for `/verify`. Do NOT run gates directly — delegate to the `verifier` subagent and narrate progress so the user sees real-time updates instead of a silent "Initializing…".

**Prerequisite:** None. The verifier resolves `scripts/run-verification-gates.sh` from the repo or, if absent, from the plugin install path via `${CLAUDE_PLUGIN_ROOT}` (zero-setup default). Run `/setup` only if you need the script vendored into the repo for CI gate authority.

Steps:

1. Print to the user:
   `▶ verifier starting`

2. Invoke the `verifier` subagent via the Task tool. Pass the user's request as input. Wait for it to return. The verifier itself runs `bash scripts/run-verification-gates.sh`, which streams `▶`/`✓`/`✗` lines per gate; the verifier surfaces those lines as they appear.

3. The verifier's response ends with a single line in the form
   `STATUS: <go|no-go|fail> | risk=<tier> | gates=<passed>/<total> | report=<path>`
   Capture that line.

4. Print ONE line to the user:
   - If STATUS starts with `STATUS: go` → `✓ verifier — <everything after "STATUS: ">`
   - Otherwise → `✗ verifier — <everything after "STATUS: ">`

5. After the verifier returns, also run the strict active-run smoke gate (this is short and produces immediate output):
   `REPORT_QUALITY_REQUIRE_CONTENT=1 WORKFLOW_REQUIRE_ARTIFACTS=1 bash scripts/smoke-bootstrap.sh`
   Print `▶ smoke gate starting` before, then `✓ smoke gate ok` (or `✗ smoke gate failed (rc=<code>)`) after.

6. Expected verifier output is `docs/verify-report.md`.
