#!/usr/bin/env bash
# Contract tests for scripts/parse-fixer-pass.sh.
#
# Covers:
#   - Accept: valid sidecar (all required fields, valid class, reason on failed)
#   - Reject (exit 1): missing key, bad class, missing reason on failed entry,
#                      unknown top-level field, .tmp path
#   - Exit 2: file not found (sidecar absent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-fixer-pass.sh"

[ -f "$PARSER" ] || { printf 'FATAL: parser missing at %s\n' "$PARSER" >&2; exit 2; }

failures=0
pass() { printf '  ok: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; failures=$(( failures + 1 )); }

# ---------------------------------------------------------------------------
# Helper: write a JSON sidecar to a temp file and return the path
# ---------------------------------------------------------------------------
_tmpdir="$(mktemp -d)"
trap 'rm -rf "$_tmpdir"' EXIT

_write_sidecar() {
  local name="$1" content="$2"
  local path="${_tmpdir}/${name}"
  printf '%s' "$content" > "$path"
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Accept: valid sidecar
# ---------------------------------------------------------------------------
printf '== Accept cases ==\n'

if command -v jq >/dev/null 2>&1; then
  VALID_SIDECAR='{
    "class": "safe_auto",
    "applied": [
      {"finding_num": 1, "file_line": "src/foo.sh:42", "title": "Use quoted variable"}
    ],
    "failed": [
      {"finding_num": 2, "file_line": "src/bar.sh:10", "title": "Remove unused import", "reason": "verify_cmd exited 1"}
    ],
    "advisory": [
      {"finding_num": 3, "file_line": "src/baz.sh:7", "title": "Consider local"}
    ]
  }'
  p="$(_write_sidecar "valid.json" "$VALID_SIDECAR")"
  bash "$PARSER" --check "$p" >/dev/null 2>&1 && pass "accept: valid safe_auto sidecar" \
    || fail "valid sidecar rejected"

  # gated_auto class
  VALID_GATED='{
    "class": "gated_auto",
    "applied": [{"finding_num": 1, "file_line": "a/b.sh:1", "title": "T"}],
    "failed": []
  }'
  p2="$(_write_sidecar "valid-gated.json" "$VALID_GATED")"
  bash "$PARSER" --check "$p2" >/dev/null 2>&1 && pass "accept: valid gated_auto sidecar" \
    || fail "gated_auto sidecar rejected"

  # manual class with empty arrays
  VALID_MANUAL='{"class":"manual","applied":[],"failed":[]}'
  p3="$(_write_sidecar "valid-manual.json" "$VALID_MANUAL")"
  bash "$PARSER" --check "$p3" >/dev/null 2>&1 && pass "accept: valid manual sidecar (empty arrays)" \
    || fail "manual sidecar with empty arrays rejected"

  # Output mode: check key=value pairs emitted
  output="$(bash "$PARSER" "$p" 2>/dev/null)"
  printf '%s\n' "$output" | grep -q "^class=safe_auto$" \
    && pass "accept: class emitted correctly" || fail "class not emitted"
  printf '%s\n' "$output" | grep -q "^applied_count=1$" \
    && pass "accept: applied_count=1 emitted" || fail "applied_count wrong"
  printf '%s\n' "$output" | grep -q "^failed_count=1$" \
    && pass "accept: failed_count=1 emitted" || fail "failed_count wrong"
  printf '%s\n' "$output" | grep -q "^failed\[0\]\.reason=verify_cmd exited 1$" \
    && pass "accept: failed reason emitted" || fail "failed reason not emitted"

  # ---------------------------------------------------------------------------
  # Reject (exit 1) cases
  # ---------------------------------------------------------------------------
  printf '\n== Reject (exit 1) cases ==\n'

  # Missing 'class' key
  NO_CLASS='{"applied":[],"failed":[]}'
  p="$(_write_sidecar "no-class.json" "$NO_CLASS")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: missing class key (exit 1)" \
    || fail "expected exit 1 for missing class, got $rc"

  # Missing 'applied' key
  NO_APPLIED='{"class":"safe_auto","failed":[]}'
  p="$(_write_sidecar "no-applied.json" "$NO_APPLIED")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: missing applied key (exit 1)" \
    || fail "expected exit 1 for missing applied, got $rc"

  # Missing 'failed' key
  NO_FAILED='{"class":"safe_auto","applied":[]}'
  p="$(_write_sidecar "no-failed.json" "$NO_FAILED")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: missing failed key (exit 1)" \
    || fail "expected exit 1 for missing failed, got $rc"

  # Bad class value
  BAD_CLASS='{"class":"unsafe_auto","applied":[],"failed":[]}'
  p="$(_write_sidecar "bad-class.json" "$BAD_CLASS")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: bad class value (exit 1)" \
    || fail "expected exit 1 for bad class, got $rc"

  # Failed entry missing reason
  MISSING_REASON='{
    "class": "safe_auto",
    "applied": [],
    "failed": [{"finding_num": 1, "file_line": "src/x.sh:5", "title": "T"}]
  }'
  p="$(_write_sidecar "missing-reason.json" "$MISSING_REASON")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: failed entry missing reason (exit 1)" \
    || fail "expected exit 1 for missing reason, got $rc"

  # Unknown top-level field
  UNKNOWN_FIELD='{"class":"safe_auto","applied":[],"failed":[],"extra_field":"oops"}'
  p="$(_write_sidecar "unknown-field.json" "$UNKNOWN_FIELD")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: unknown top-level field (exit 1)" \
    || fail "expected exit 1 for unknown field, got $rc"

  # Applied entry missing file_line
  MISSING_FL='{
    "class": "safe_auto",
    "applied": [{"finding_num": 1, "title": "T"}],
    "failed": []
  }'
  p="$(_write_sidecar "missing-fileline.json" "$MISSING_FL")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: applied entry missing file_line (exit 1)" \
    || fail "expected exit 1 for missing file_line, got $rc"

  # Applied entry bad file_line format (no colon+number)
  BAD_FL='{
    "class": "safe_auto",
    "applied": [{"finding_num": 1, "file_line": "just-a-path", "title": "T"}],
    "failed": []
  }'
  p="$(_write_sidecar "bad-fileline.json" "$BAD_FL")"
  rc=0; bash "$PARSER" --check "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 1 ] && pass "reject: bad file_line format (exit 1)" \
    || fail "expected exit 1 for bad file_line, got $rc"

else
  printf '  SKIP: jq not available; most reject tests skipped (jq required for schema validation)\n'
fi

# ---------------------------------------------------------------------------
# .tmp path rejection (exit 1) — no jq needed
# ---------------------------------------------------------------------------
printf '\n== .tmp path rejection ==\n'
TMP_PATH="${_tmpdir}/fixer-pass-safe_auto.json.tmp"
printf '{}' > "$TMP_PATH"
rc=0; bash "$PARSER" --check "$TMP_PATH" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 1 ] && pass "reject: .tmp-suffixed path (exit 1)" \
  || fail "expected exit 1 for .tmp path, got $rc"

# ---------------------------------------------------------------------------
# Exit 2: file not found
# ---------------------------------------------------------------------------
printf '\n== Exit 2: file not found ==\n'
rc=0; bash "$PARSER" --check "${_tmpdir}/nonexistent-sidecar.json" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "exit 2: missing sidecar" \
  || fail "expected exit 2 for missing file, got $rc"

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
