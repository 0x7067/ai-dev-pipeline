# Adversarial Code Review Report

Date: 2026-02-22
Scope: `.claude/`, `scripts/`, and workflow policy docs in this repository.
Recommendation: Request changes.

## Research Baseline

Primary sources used before auditing code:
- Claude Code Hooks documentation (hook input format, decision control, and event behavior): https://docs.anthropic.com/en/docs/claude-code/hooks
- Claude Code common hook patterns (file protection pattern with JSON parsing via `jq`): https://docs.anthropic.com/en/docs/claude-code/hooks#common-hook-patterns
- npm run-script documentation (`npm run` executes scripts; `--if-present` behavior): https://docs.npmjs.com/cli/v11/commands/npm-run-script
- GNU Coreutils `mktemp` documentation (temporary-file race/clobber risk with predictable names): https://www.gnu.org/software/coreutils/manual/html_node/mktemp-invocation.html
- CWE-377 (Insecure Temporary File): https://cwe.mitre.org/data/definitions/377.html

Repo-local policy sources:
- `.claude/rules/security-baseline.md` (sensitive files include `.env*`)
- `.claude/rules/release-and-verification.md` (type/lint/test failures are blocking)

## Findings (Highest Severity First)

### High: Protected-file gate is bypassable for actual hook payloads and misses `.env.*`
- Location: `.claude/hooks/protect-files.sh:4`, `.claude/hooks/protect-files.sh:6-13`, `.claude/rules/security-baseline.md:13-15`
- Why this is a problem:
  - Claude hooks provide structured JSON input; this script regex-scans raw payload text and anchors to end-of-line, so normal JSON payloads do not match protected paths.
  - The regex uses `\.env\.` instead of a `.env*` pattern, so `.env.local` is not protected even with plain path input.
  - Result: secret file edits can pass the PreToolUse guard despite policy stating `.env*` is sensitive.
- Evidence:
  - JSON payload bypass reproductions:
    - `printf '{"tool_input":{"file_path":"/tmp/.env"}}' | bash .claude/hooks/protect-files.sh; echo EXIT:$?` -> `EXIT:0`
    - `printf '{"tool_input":{"file_path":"/tmp/cert.key"}}' | bash .claude/hooks/protect-files.sh; echo EXIT:$?` -> `EXIT:0`
  - Plain path bypass for `.env.local`:
    - `printf '/tmp/.env.local\n' | bash .claude/hooks/protect-files.sh; echo EXIT:$?` -> `EXIT:0`
- Supporting docs:
  - Hooks input is JSON and common protection pattern extracts file path with `jq`.
- Recommended fix:
  - Parse JSON payload (`tool_input.file_path`) with `jq` and check extracted paths only.
  - Replace `.env` pattern with `.env` plus optional suffix, e.g. `(^|/)\.env(\..+)?$`.
  - Keep exit code `2` for block behavior, but ensure matches run against normalized path strings, not full JSON blobs.

### High: Type-check and lint hooks fail open when checks fail
- Location: `.claude/hooks/type-check.sh:9-35`, `.claude/hooks/lint-on-edit.sh:9-35`, `.claude/rules/release-and-verification.md:3-10`
- Why this is a problem:
  - The scripts use command execution as a capability probe (`if npm run -s <script> >/dev/null 2>&1; then ...`).
  - If a script exists but returns non-zero (actual lint/type errors), the condition is false and the hook continues to fallback branches, often ending in `skipped` with exit `0`.
  - This masks real failures and violates the repo's own blocking-gate policy.
- Evidence:
  - Reproduction with mocked `npm` returning exit `1` for `run -s typecheck`:
    - Hook output: `type-check: skipped (no supported typecheck command found)`
    - Exit code: `0`
  - Reproduction with mocked `npm` returning exit `1` for `run -s lint`:
    - Hook output: `lint-on-edit: skipped (no supported lint command found)`
    - Exit code: `0`
- Supporting docs:
  - `npm run` executes the script; `--if-present` is the flag designed for "missing script" behavior.
- Recommended fix:
  - Do not run checks twice or use execution as existence probing.
  - Execute each selected check once and propagate non-zero exits.
  - Distinguish "missing script" vs "script failed" using package metadata checks or `--if-present` where supported.

### Medium: Stop formatter executes format command twice
- Location: `.claude/hooks/format-on-stop.sh:9-35`
- Why this is a problem:
  - The hook first runs `npm|bun|pnpm|yarn ... format` in a conditional probe, then runs it again via `run` on success.
  - This doubles runtime and can duplicate non-idempotent side effects in custom format scripts.
- Evidence:
  - Reproduction with mocked `npm` counting invocations:
    - Hook output: `format-on-stop: npm run -s format`
    - Invocation count: `2`
- Supporting docs:
  - `npm run` executes the named script each invocation.
- Recommended fix:
  - Remove probe execution. Detect script availability from metadata or run once and handle missing-script exit semantics explicitly.

### Medium: Boundary-check script uses predictable `/tmp` file and can clobber arbitrary target via symlink
- Location: `scripts/check-boundary-violations.sh:18-20`
- Why this is a problem:
  - The script redirects to a fixed world-writable path (`/tmp/boundary_hits.txt`) without `mktemp`.
  - An attacker (or parallel process) can pre-create a symlink at that path and force truncation/overwrite of another file.
  - Because redirection occurs before `rg` runs, the target can be truncated even when a check has no matches.
- Evidence:
  - Reproduction:
    - `ln -sf /tmp/boundary-symlink-repro/target.txt /tmp/boundary_hits.txt`
    - Running boundary check truncated the symlink target (`TARGET_CONTENT:` became empty).
- Supporting docs:
  - GNU `mktemp` warns against predictable temp names; CWE-377 classifies this as insecure temporary file usage.
- Recommended fix:
  - Use `tmp_file="$(mktemp)"` and `trap 'rm -f "$tmp_file"' EXIT`.
  - Avoid global fixed temp paths.

## Open Questions / Assumptions
- Assumption: hooks are intended to enforce policy, not only provide advisory feedback.
- Assumption: `.env*` protection should apply to both plain and JSON tool inputs (consistent with `security-baseline.md`).

## Residual Risks
- Hook behavior under all Claude client versions was not exhaustively replayed; findings rely on current documented hook contract and local script behavior.
- No language-runtime source tree (`src/`) exists yet, so boundary-check quality was validated only at script level, not against real app modules.

## Brief Summary
- Secret-file protection is currently bypassable under normal JSON hook payloads.
- Lint/typecheck hooks can report `skipped` and exit `0` even when checks fail.
- Formatter hook runs scripts twice, increasing latency and side-effect risk.
- Boundary check uses insecure temporary-file handling in `/tmp`.
- Overall recommendation: **Request changes** before relying on this bootstrap as a security/quality gate.
