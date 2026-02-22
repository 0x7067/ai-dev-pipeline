# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|

## User Preferences
- Keep communication concise and pragmatic.
- Use findings-first structure for review requests with file/line references.

## Patterns That Work
- Prefer `rg`/`sed` for quick local analysis.
- Verify externally when user asks for research or current-state validation.

## Patterns That Don't Work
- N/A yet.

## Domain Notes
- Repo: `ai-dev-pipeline`.
- Maintain this file continuously during work sessions.

## Session Notes 2026-02-22
- For external report reviews, verify product-behavior claims against official docs first; many ecosystem posts echo unsourced numbers.
- If a report includes precise percentages without citations (e.g., "70% improvement"), treat as unverified until primary evidence is found.
- Greenfield repos need a validation-first bootstrap (settings + schema checks) before large skill/agent fan-out.
- Use official Claude docs paths (`code.claude.com/docs/en/...`) as primary source for implementation semantics.
- Environment surprise: `/Users/pedro/Development/personal/ai-dev-pipeline` currently has no `.git`; avoid git-dependent automation unless repo is initialized.
- Correction: repo is now git-initialized; deployment/version automation may proceed in this root.
- Debugging lesson: frontmatter validators must explicitly handle `---` before list-item regex to avoid false references.
- Reuse win: provide one smoke command with stable machine-readable output (`RESULT|...`, `SUMMARY|...`) for CI parsing across projects.
- Adversarial review finding: regex-scanning raw hook payloads is fragile; parse JSON hook input with `jq` before policy checks.
- Gate design note: never use `npm run <script>` as a capability probe because failures are indistinguishable from missing scripts unless checked explicitly.
- Repro note: fixed `/tmp/<name>` redirections in validation scripts are symlink-clobber risks; prefer `mktemp` with cleanup trap.
- Self-correction: while mocking PATH for hook tests, removing system binaries caused false negatives (`bash` missing). Keep `/bin:/usr/bin` in PATH when running wrapper scripts.
- Fix pattern applied: determine script presence from `package.json` (`jq`/regex fallback), then execute selected check exactly once and propagate exit code.
- Medium-risk hardening pattern: remove "probe-by-execution" in formatter hooks and use `mktemp` + `trap` for all temporary files in shared directories.
