#!/usr/bin/env bash
# Contract test: scripts/parse-phase-timings.sh accept/reject behavior.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-phase-timings.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

tmpdir=$(mktemp -d -t phase-timings.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

# --- Accept: well-formed v1 file ---
cat > "$tmpdir/good.json" <<'EOF'
{
  "schema_version": 1,
  "phases": [
    { "name": "plan", "status": "ok", "seconds": 3, "started_at": "2026-05-09T10:00:00Z" },
    { "name": "implement", "status": "ok", "seconds": 70, "started_at": "2026-05-09T10:00:03Z" }
  ],
  "total_seconds": 73
}
EOF

if out=$(bash "$PARSER" "$tmpdir/good.json" 2>&1); then
  if grep -q '^phase_count=2$' <<<"$out" \
     && grep -q '^total_seconds=73$' <<<"$out" \
     && grep -q '^phase_1_name=plan$' <<<"$out" \
     && grep -q '^phase_2_seconds=70$' <<<"$out"; then
    pass "well-formed v1 accepted"
  else
    fail "good.json output unexpected: $out"
  fi
else
  fail "good.json rejected unexpectedly: $out"
fi

# --- Reject: malformed JSON ---
echo "{not json" > "$tmpdir/malformed.json"
out=$(bash "$PARSER" "$tmpdir/malformed.json" 2>&1)
rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "malformed.json"; then
  pass "malformed JSON rejected with rc=2 and file in stderr"
else
  fail "malformed JSON: rc=$rc out=$out"
fi

# --- Reject: missing required fields ---
cat > "$tmpdir/missing_field.json" <<'EOF'
{ "schema_version": 1, "phases": [ { "name": "plan", "status": "ok", "seconds": 3 } ], "total_seconds": 3 }
EOF
out=$(bash "$PARSER" "$tmpdir/missing_field.json" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "missing started_at rejected with rc=2"
else
  fail "missing field: expected rc=2, got rc=$rc out=$out"
fi

# --- Reject: bad schema_version ---
cat > "$tmpdir/bad_schema.json" <<'EOF'
{ "schema_version": 2, "phases": [], "total_seconds": 0 }
EOF
out=$(bash "$PARSER" "$tmpdir/bad_schema.json" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "wrong schema_version rejected with rc=2"
else
  fail "bad schema: rc=$rc out=$out"
fi

# --- Reject: missing file ---
out=$(bash "$PARSER" "$tmpdir/does-not-exist.json" 2>&1)
rc=$?
if [ "$rc" -eq 2 ]; then
  pass "missing file rejected with rc=2"
else
  fail "missing file: rc=$rc"
fi

if [ "$failures" -eq 0 ]; then
  echo "parse-phase-timings: PASS"
  exit 0
fi
echo "parse-phase-timings: FAIL ($failures)" >&2
exit 1
