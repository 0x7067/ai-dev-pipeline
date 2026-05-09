# `decisions.jsonl` Schema (v1)

`${RUN_DIR}/decisions.jsonl` is the per-run audit log of every gate
event in the `/ship` and `/refactor` pipelines. One JSON object per
line. The encoder is `decision_record_build` (core, pure) in
`scripts/lib/decisions-core.sh`; the appender is
`scripts/append-decision.sh` (shell). The parser is
`decision_record_parse` (core, pure) in the same library.

## Record shape

```json
{"ts":"<iso8601-utc>","actor":"<user|auto|time-box>","gate":"<plan|release|refactor-plan>","verb":"<approve|edit|reject>","rationale":"<short-text>","plan_hash":"<hex-or-empty>"}
```

| Field       | Type   | Notes                                                                |
|-------------|--------|----------------------------------------------------------------------|
| `ts`        | string | ISO-8601 UTC, caller-supplied (no ambient clock — FC purity).        |
| `actor`     | enum   | `user` (human reply), `auto` (orchestrator auto-approve), `time-box` (deadline elapse). |
| `gate`      | enum   | `plan`, `release`, or `refactor-plan`.                               |
| `verb`      | enum   | `approve`, `edit`, or `reject`. `edit` is plan-gate only — invariant 8 of the HITL plan. |
| `rationale` | string | Free-form short text. No newlines or ANSI escapes.                   |
| `plan_hash` | string | Hex digest of the current plan, or empty string if not applicable.   |

## Invariants

1. **Audit completeness.** Exactly one record per gate transition (HITL
   plan invariant 2).
2. **Round-trip.** `decision_record_parse(decision_record_build(x)) == x`
   for every record (HITL plan invariant 3).
3. **No ANSI.** Records contain zero ANSI escape sequences (HITL plan
   invariant 6).

## Atomicity

The appender uses `flock` when available, falling back to a single
`printf >> file` (atomic up to `PIPE_BUF` on POSIX, comfortably above
the canonical record size). Records are line-aligned; partial writes
across concurrent appenders cannot interleave.

## References

- `.claude/rules/architecture-fcis.md` — pure core, shell appender.
- `.claude/rules/boundary-parse-dont-validate.md` — JSONL is parsed
  back into typed records before any consumer branches on it.
- `.claude/rules/release-and-verification.md` — gate authority and
  release approval policy.
