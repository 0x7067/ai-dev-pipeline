#!/usr/bin/env bash
# Contract tests for scripts/parse-pending-approval.sh +
# scripts/queue-pending-approval.sh.
#
# Per .claude/rules/boundary-parse-dont-validate.md, the marker file is
# untrusted ingress. Per HITL plan invariant 9, the writer is atomic.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

RUN_ID='20260509T100000-abc123-7f'
mkdir -p "$tmp/runs/$RUN_ID"

# Round-trip: queue then parse.
out="$(bash "${REPO_ROOT}/scripts/queue-pending-approval.sh" \
  --run-dir "$tmp/runs/$RUN_ID" \
  --run-id "$RUN_ID" \
  --gate plan \
  --deadline-iso 2026-05-09T11:00:00Z \
  --plan-hash deadbeef \
  --created-at 2026-05-09T10:00:00Z 2>&1)" \
  && pass "queue write" || { fail "queue write: $out"; exit 1; }

[ -f "$tmp/runs/$RUN_ID/.pending-approval.json" ] && pass "marker exists" || fail "marker missing"

parsed="$(bash "${REPO_ROOT}/scripts/parse-pending-approval.sh" \
  "$tmp/runs/$RUN_ID/.pending-approval.json" 2>&1)" \
  && pass "parse accept" || { fail "parse: $parsed"; }

echo "$parsed" | grep -q "^run_id=$RUN_ID$" && pass "run_id round-trip" || fail "run_id mismatch"
echo "$parsed" | grep -q '^gate=plan$' && pass "gate round-trip" || fail "gate mismatch"
echo "$parsed" | grep -q '^plan_hash=deadbeef$' && pass "plan_hash round-trip" || fail "plan_hash mismatch"

# Reject: malformed JSON.
printf 'not json\n' > "$tmp/bad.json"
bash "${REPO_ROOT}/scripts/parse-pending-approval.sh" "$tmp/bad.json" >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad json rejected" || fail "bad json accepted"

# Reject: bad run_id.
printf '{"run_id":"badid","gate":"plan","deadline_iso":"","plan_hash":"","created_at":"2026-05-09T10:00:00Z"}\n' \
  > "$tmp/badid.json"
bash "${REPO_ROOT}/scripts/parse-pending-approval.sh" "$tmp/badid.json" >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad run_id rejected" || fail "bad run_id accepted"

# Reject: bad gate.
printf '{"run_id":"%s","gate":"haunted","deadline_iso":"","plan_hash":"","created_at":"2026-05-09T10:00:00Z"}\n' \
  "$RUN_ID" > "$tmp/badgate.json"
bash "${REPO_ROOT}/scripts/parse-pending-approval.sh" "$tmp/badgate.json" >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad gate rejected" || fail "bad gate accepted"

# Writer rejects bad gate.
bash "${REPO_ROOT}/scripts/queue-pending-approval.sh" \
  --run-dir "$tmp/runs/$RUN_ID" \
  --run-id "$RUN_ID" \
  --gate haunted \
  --created-at 2026-05-09T10:00:00Z >/dev/null 2>&1
[ $? -eq 2 ] && pass "writer rejects bad gate" || fail "writer accepted bad gate"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures" >&2
  exit 1
fi
echo "OK"
