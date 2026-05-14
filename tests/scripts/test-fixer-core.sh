#!/usr/bin/env bash
# Unit tests for scripts/lib/fixer-core.sh.
#
# Covers:
#   - fixer_partition_queue: correct 3-way split by autofix_class
#   - fixer_precheck_finding: ok and stale cases
#   - fixer_gate_pass: run/skip table (applied=0 → skip; applied>=1, error=0 → run;
#                       error=1 → skip regardless of applied)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
LIB="${REPO_ROOT}/scripts/lib/fixer-core.sh"

[ -f "$LIB" ] || { printf 'FATAL: lib missing at %s\n' "$LIB" >&2; exit 2; }
# shellcheck source=/dev/null
source "$LIB"

failures=0
pass() { printf '  ok: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; failures=$(( failures + 1 )); }

# ---------------------------------------------------------------------------
# fixer_precheck_finding
# ---------------------------------------------------------------------------
printf '== fixer_precheck_finding ==\n'

result="$(fixer_precheck_finding "int main() { return 0; }" "main")"
[ "$result" = "ok" ] && pass "precheck ok: token present" || fail "expected ok, got: $result"

result="$(fixer_precheck_finding "int main() { return 0; }" "foobar")"
[ "$result" = "stale" ] && pass "precheck stale: token absent" || fail "expected stale, got: $result"

result="$(fixer_precheck_finding 'UNQUOTED_VAR=$x' "UNQUOTED_VAR")"
[ "$result" = "ok" ] && pass "precheck ok: exact token match" || fail "got: $result"

# Empty token should fail (return non-zero).
fixer_precheck_finding "some text" "" >/dev/null 2>&1 && fail "empty token should fail" \
  || pass "precheck rejects empty token"

# ---------------------------------------------------------------------------
# fixer_gate_pass
# ---------------------------------------------------------------------------
printf '\n== fixer_gate_pass ==\n'

# applied=0, error=0 → skip (nothing applied, no error)
result="$(fixer_gate_pass 0 0 0)"
[ "$result" = "skip" ] && pass "gate: applied=0 error=0 → skip" || fail "expected skip, got: $result"

# applied=0, failed=5, error=0 → skip
result="$(fixer_gate_pass 0 5 0)"
[ "$result" = "skip" ] && pass "gate: applied=0 failed=5 error=0 → skip" || fail "expected skip, got: $result"

# applied=1, failed=0, error=0 → run
result="$(fixer_gate_pass 1 0 0)"
[ "$result" = "run" ] && pass "gate: applied=1 error=0 → run" || fail "expected run, got: $result"

# applied=5, failed=3, error=0 → run (partial success is ok per OD-1)
result="$(fixer_gate_pass 5 3 0)"
[ "$result" = "run" ] && pass "gate: applied=5 failed=3 error=0 → run" || fail "expected run, got: $result"

# applied=10, failed=0, error=1 → skip (orchestrator error overrides)
result="$(fixer_gate_pass 10 0 1)"
[ "$result" = "skip" ] && pass "gate: applied=10 error=1 → skip" || fail "expected skip, got: $result"

# applied=0, failed=0, error=1 → skip
result="$(fixer_gate_pass 0 0 1)"
[ "$result" = "skip" ] && pass "gate: applied=0 error=1 → skip" || fail "expected skip, got: $result"

# Bad inputs should return non-zero.
fixer_gate_pass "abc" 0 0 >/dev/null 2>&1 && fail "non-int applied_count accepted" \
  || pass "gate rejects non-int applied_count"

fixer_gate_pass 1 0 2 >/dev/null 2>&1 && fail "error_flag=2 accepted" \
  || pass "gate rejects error_flag=2"

fixer_gate_pass 1 -1 0 >/dev/null 2>&1 && fail "negative failed_count accepted" \
  || pass "gate rejects negative failed_count"

# ---------------------------------------------------------------------------
# fixer_partition_queue
# ---------------------------------------------------------------------------
printf '\n== fixer_partition_queue ==\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: jq not available; fixer_partition_queue tests skipped\n'
else
  # Fixture: 5 findings across 3 classes.
  FIXTURE='[
    {"finding_num":1,"autofix_class":"safe_auto","title":"A"},
    {"finding_num":2,"autofix_class":"gated_auto","title":"B"},
    {"finding_num":3,"autofix_class":"manual","title":"C"},
    {"finding_num":4,"autofix_class":"safe_auto","title":"D"},
    {"finding_num":5,"autofix_class":"gated_auto","title":"E"}
  ]'

  output="$(fixer_partition_queue "$FIXTURE")"

  # safe_auto section should have findings 1 and 4
  safe_section="$(printf '%s\n' "$output" | \
    awk '/^safe_auto$/{p=1;next}/^gated_auto$/{p=0}p')"
  count_safe="$(printf '%s\n' "$safe_section" | grep -c '"finding_num"' 2>/dev/null || true)"
  [ "$count_safe" -eq 2 ] && pass "partition: 2 safe_auto findings" \
    || fail "expected 2 safe_auto, got $count_safe"

  # gated_auto section should have findings 2 and 5
  gated_section="$(printf '%s\n' "$output" | \
    awk '/^gated_auto$/{p=1;next}/^manual$/{p=0}p')"
  count_gated="$(printf '%s\n' "$gated_section" | grep -c '"finding_num"' 2>/dev/null || true)"
  [ "$count_gated" -eq 2 ] && pass "partition: 2 gated_auto findings" \
    || fail "expected 2 gated_auto, got $count_gated"

  # manual section should have finding 3
  manual_section="$(printf '%s\n' "$output" | \
    awk '/^manual$/{p=1}p' | tail -n +2)"
  count_manual="$(printf '%s\n' "$manual_section" | grep -c '"finding_num"' 2>/dev/null || true)"
  [ "$count_manual" -eq 1 ] && pass "partition: 1 manual finding" \
    || fail "expected 1 manual, got $count_manual"

  # Unknown class → manual
  UNKNOWN='[{"finding_num":6,"autofix_class":"unknown_class","title":"F"}]'
  out2="$(fixer_partition_queue "$UNKNOWN")"
  unknown_manual="$(printf '%s\n' "$out2" | \
    awk '/^manual$/{p=1}p' | tail -n +2)"
  count_u="$(printf '%s\n' "$unknown_manual" | grep -c '"finding_num"' 2>/dev/null || true)"
  [ "$count_u" -eq 1 ] && pass "partition: unknown class → manual" \
    || fail "expected 1 in manual for unknown class, got $count_u"

  # Missing autofix_class → manual
  MISSING='[{"finding_num":7,"title":"G"}]'
  out3="$(fixer_partition_queue "$MISSING")"
  missing_manual="$(printf '%s\n' "$out3" | \
    awk '/^manual$/{p=1}p' | tail -n +2)"
  count_m="$(printf '%s\n' "$missing_manual" | grep -c '"finding_num"' 2>/dev/null || true)"
  [ "$count_m" -eq 1 ] && pass "partition: missing autofix_class → manual" \
    || fail "expected 1 in manual for missing class, got $count_m"

  # Empty array → all sections empty (no findings lines, sections still present)
  out4="$(fixer_partition_queue "[]")"
  if printf '%s\n' "$out4" | grep -q '^safe_auto$'; then
    pass "partition: empty array emits all section headers"
  else
    fail "empty array did not emit safe_auto header"
  fi
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
printf '\n'
if [ "$failures" -eq 0 ]; then
  printf 'ALL TESTS PASSED\n'
  exit 0
else
  printf 'FAILURES: %d\n' "$failures" >&2
  exit 1
fi
