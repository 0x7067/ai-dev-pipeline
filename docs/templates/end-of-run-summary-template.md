# End-of-Run Artifact Summary

This template is rendered by every primary command (`/ship`, `/review`,
`/refactor`, `/audit`, `/research`) as the last block of console output. It
gives the user one place to copy-paste the run-id and walk every artifact the
pipeline produced. Keep the rendered block under ~10 lines.

## Render contract

After all phases complete (success or halt), print exactly this block,
substituting the live values. Use absolute paths (resolve `${RUN_DIR}` to its
absolute form). Omit lines for artifacts that do not exist on disk —
**do not print empty stubs** — but always keep the `RUN_ID` and `RUN_DIR`
header lines. Mark each present artifact with `✓`.

```
─ Run summary ─────────────────────────────────────────
RUN_ID: <run-id>
RUN_DIR: <absolute path to ${RUN_DIR}>
Artifacts:
  ✓ plan          <abs>/current-plan.md
  ✓ specs         <abs>/specs/            (N file(s))
  ✓ research      <abs>/research/         (N file(s))
  ✓ test-report   <abs>/test-report.md
  ✓ review-report <abs>/review-report.md
  ✓ verify-report <abs>/verify-report.md
  ✓ impl-summary  <abs>/impl-summary.md
  ✓ refactor      <abs>/refactor-report.md
  ✓ audit         <abs>/audit-report.md
───────────────────────────────────────────────────────
```

## Implementation hint (bash)

```sh
abs_run_dir="$(cd "$RUN_DIR" 2>/dev/null && pwd -P)"
printf '─ Run summary ─────────────────────────────────────────\n'
printf 'RUN_ID: %s\n' "$RUN_ID"
printf 'RUN_DIR: %s\n' "$abs_run_dir"
printf 'Artifacts:\n'
for pair in \
  "plan:current-plan.md" \
  "test-report:test-report.md" \
  "review-report:review-report.md" \
  "verify-report:verify-report.md" \
  "impl-summary:impl-summary.md" \
  "refactor:refactor-report.md" \
  "audit:audit-report.md"; do
  label="${pair%%:*}"; rel="${pair#*:}"
  [ -s "${abs_run_dir}/${rel}" ] && printf '  ✓ %-13s %s/%s\n' "$label" "$abs_run_dir" "$rel"
done
for dir in specs research; do
  if [ -d "${abs_run_dir}/${dir}" ]; then
    n=$(find "${abs_run_dir}/${dir}" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && printf '  ✓ %-13s %s/%s/ (%s file(s))\n' "$dir" "$abs_run_dir" "$dir" "$n"
  fi
done
printf '───────────────────────────────────────────────────────\n'
```

The exact rendering script is non-normative — what matters is that every
primary command prints this block (and only this block) at the very end, with
absolute paths and only the artifacts that actually exist.
