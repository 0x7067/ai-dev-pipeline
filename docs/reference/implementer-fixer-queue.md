# Implementer Fixer-Queue Mode

Reference for the `implementer` agent when invoked with a `<fixer-queue>`
envelope by `ce-code-review-local`'s 3-pass dispatcher. The default `/ship`
implementer path does NOT need this file.

## Activation

Triggered when the caller prepends this XML envelope to the implementer prompt:

```
<fixer-queue class="safe_auto|gated_auto|manual">
[{"finding_num":1,"file":"src/foo.sh","line":42,"title":"Use quoted variable","suggested_fix":"Quote $VAR as \"$VAR\"","evidence":["UNQUOTED_VAR"],"verify_cmd":"bash -n src/foo.sh"},...]
</fixer-queue>
```

Without the tag, the implementer behaves normally (backward-compatible).

## Finding object schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `finding_num` | integer ≥ 1 | yes | 1-based index from the review queue |
| `file` | string | yes | Relative or absolute path |
| `line` | integer ≥ 1 | yes | Line number of the finding |
| `title` | string | yes | Short description |
| `suggested_fix` | string | yes | Prose or patch for the desired change |
| `evidence` | string[] | yes | Distinctive tokens expected near file:line |
| `verify_cmd` | string | no | Shell command to run after applying |

## Per-finding protocol

For each finding, in order:

1. **Read window.** Read ±5 lines around `file:line`. If the file is missing
   or the line is out of range → `failed`, reason `"stale: file not found or
   line out of range"`.
2. **Evidence precheck.** Every token in `evidence[]` must appear verbatim in
   the window (use `fixer_precheck_finding` from `scripts/lib/fixer-core.sh`).
   Any missing token → `failed`, reason `"stale: evidence token not found:
   <token>"`. Do NOT apply the fix.
3. **Apply fix** to the indicated location.
4. **Run `verify_cmd`** if present. Non-zero exit → `failed`, reason
   `"verify_cmd exited <N>: <cmd>"`. Continue with remaining findings.
5. **Record** the outcome in the in-memory `applied` or `failed` list.

## Sidecar write

At end of pass:

1. Write `${RUN_DIR}/.fixer-pass-<class>.json.tmp`.
2. Rename to `${RUN_DIR}/fixer-pass-<class>.json`.

Shape (conforms to `docs/schemas/fixer-pass-v1.schema.json`):

```json
{
  "class": "<class>",
  "applied": [{"finding_num":1,"file_line":"src/foo.sh:42","title":"Use quoted variable"}],
  "failed":  [{"finding_num":2,"file_line":"src/bar.sh:10","title":"Remove unused import","reason":"verify_cmd exited 1: bash -n src/bar.sh"}],
  "advisory": []
}
```

## Invariants

- Every input finding lands in exactly one of `applied` or `failed`.
- A `verify_cmd` failure isolates to that finding; the pass continues.
- Precheck failure → `failed` without attempting the fix.
- Atomic write via tmp+rename; a `.tmp` left behind on early exit is
  abandoned and the parser returns exit 2 (sidecar absent), not a parse error.

## References

- Sidecar schema: `docs/schemas/fixer-pass-v1.schema.json`
- Core helpers: `scripts/lib/fixer-core.sh`
- Boundary parser: `scripts/parse-fixer-pass.sh`
- 3-pass orchestration: `.claude/skills/ce-code-review-local/SKILL.md`
