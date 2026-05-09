#!/usr/bin/env bash
# Property tests for scripts/lib/hitl-core.sh.
#
# Covers HITL plan invariants:
#   I1 auto-approve safety (only fires on the exact tuple; any noise → prompt/reject)
#   I4 time injection: same inputs → same output
#   I5 time-box monotonicity

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
LIB="${REPO_ROOT}/scripts/lib/hitl-core.sh"
[ -f "$LIB" ] || { echo "lib missing at $LIB" >&2; exit 2; }
# shellcheck source=/dev/null
source "$LIB"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# --- risk_rationale_format ---
out="$(risk_rationale_format medium 'cross-module change')"
[ "$out" = "risk=medium because cross-module change" ] \
  && pass "rationale format" || fail "rationale: $out"

risk_rationale_format invalid 'x' >/dev/null 2>&1
[ $? -eq 2 ] && pass "rationale rejects bad tier" || fail "bad tier accepted"

risk_rationale_format low $'has\nnewline' >/dev/null 2>&1
[ $? -eq 2 ] && pass "rationale rejects newline" || fail "newline accepted"

# --- policy_apply: auto-approve only on the exact tuple (I1) ---
out="$(policy_apply auto low 0 go passed)"
[ "$out" = "auto-approve" ] && pass "auto-approve canonical" || fail "expected auto-approve, got $out"

# Each variant should NOT auto-approve.
declare -a not_auto=(
  'strict low 0 go passed'
  'auto medium 0 go passed'
  'auto low 1 go passed'
  'auto low 0 no-go passed'
  'auto low 0 go failed'
  'auto unknown 0 go passed'
)
for c in "${not_auto[@]}"; do
  # shellcheck disable=SC2086
  out="$(policy_apply $c)"
  [ "$out" != "auto-approve" ] \
    && pass "no auto-approve for: $c → $out" \
    || fail "auto-approve leaked: $c"
done

# Garbage inputs MUST NOT auto-approve.
declare -a junk=(
  'auto low 0 go xxxx'
  'auto low x go passed'
  'AUTO low 0 go passed'
  'auto critical 0 go passed'
  '" " " " "'
)
for c in "${junk[@]}"; do
  # shellcheck disable=SC2086
  out="$(policy_apply $c 2>/dev/null)"
  [ "$out" != "auto-approve" ] \
    && pass "fail-closed: $c → $out" \
    || fail "auto-approve on junk: $c"
done

# --- reject-reason audit hint on stderr (advisory fix) ---
# Primary stdout contract is unchanged ("reject"); stderr carries a
# typed reason so the audit log can distinguish verifier crash from
# gates-failed from smoke-failed.
out="$(policy_apply auto low 0 fail passed 2>/dev/null)"
[ "$out" = "reject" ] && pass "verifier=fail → reject" || fail "verifier=fail expected reject got $out"
err="$(policy_apply auto low 0 fail passed 2>&1 1>/dev/null)"
echo "$err" | grep -q '^reject-reason=verifier-crashed$' \
  && pass "verifier=fail → reject-reason=verifier-crashed" \
  || fail "verifier=fail reason: $err"

err="$(policy_apply auto low 0 no-go passed 2>&1 1>/dev/null)"
echo "$err" | grep -q '^reject-reason=gates-failed$' \
  && pass "verifier=no-go → reject-reason=gates-failed" \
  || fail "verifier=no-go reason: $err"

err="$(policy_apply auto low 0 go failed 2>&1 1>/dev/null)"
echo "$err" | grep -q '^reject-reason=smoke-failed$' \
  && pass "smoke=failed → reject-reason=smoke-failed" \
  || fail "smoke=failed reason: $err"

# --- determinism (I4) ---
a="$(policy_apply auto low 0 go passed)"
b="$(policy_apply auto low 0 go passed)"
[ "$a" = "$b" ] && pass "determinism" || fail "non-deterministic"

# --- refactor_scope_classify ---
[ "$(refactor_scope_classify 5 100 10 300)" = "below" ] && pass "scope below" || fail "scope below"
[ "$(refactor_scope_classify 11 100 10 300)" = "above" ] && pass "scope above by files" || fail "above-by-files"
[ "$(refactor_scope_classify 5 400 10 300)" = "above" ] && pass "scope above by loc" || fail "above-by-loc"
[ "$(refactor_scope_classify 10 300 10 300)" = "below" ] && pass "scope at boundary" || fail "boundary"

# --- time_box_resolve monotonicity (I5) ---
deadline=1000
prev_expired=""
for now in 100 500 999 1000 1001 2000; do
  out="$(time_box_resolve "$now" "$deadline")"
  exp="$(echo "$out" | sed -n 's/^expired=//p')"
  if [ -n "$prev_expired" ] && [ "$prev_expired" = "true" ] && [ "$exp" != "true" ]; then
    fail "monotonicity broke at now=$now"
  fi
  prev_expired="$exp"
done
pass "time-box monotonicity"

# Determinism for time_box_resolve.
a="$(time_box_resolve 100 1000)"
b="$(time_box_resolve 100 1000)"
[ "$a" = "$b" ] && pass "time-box determinism" || fail "time-box non-deterministic"

# Boundary: now == deadline → expired=true.
out="$(time_box_resolve 1000 1000)"
echo "$out" | grep -q '^expired=true$' && pass "deadline boundary expired=true" || fail "deadline boundary"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures" >&2
  exit 1
fi
echo "OK"
