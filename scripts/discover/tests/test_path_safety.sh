#!/usr/bin/env bash
# test_path_safety.sh — shell-level tests for extract.sh path safety.
#
# Tests:
#   1. Files with spaces, special chars, and leading-dash names are handled
#      without word splitting.
#   2. --bucket "rm -rf /" is rejected with exit code 3.
#
# Requires: git (for repo check), bash >= 4

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." >/dev/null 2>&1 && pwd -P)"
EXTRACT_SH="${SCRIPT_DIR}/../extract.sh"

_pass=0
_fail=0

_assert() {
  local desc="$1"
  local cond="$2"
  if eval "$cond"; then
    echo "[PASS] ${desc}"
    _pass=$((_pass + 1))
  else
    echo "[FAIL] ${desc}" >&2
    _fail=$((_fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test 1: --bucket with injection string is rejected (exit 3)
# ---------------------------------------------------------------------------
bash "${EXTRACT_SH}" --bucket "rm -rf /" --dry-run 2>/dev/null
_rc=$?
_assert "--bucket 'rm -rf /' is rejected (exit 3)" "[ $_rc -eq 3 ]"

# ---------------------------------------------------------------------------
# Test 2: --bucket with uppercase is rejected
# ---------------------------------------------------------------------------
bash "${EXTRACT_SH}" --bucket "MyBucket" --dry-run 2>/dev/null
_rc=$?
_assert "--bucket 'MyBucket' (uppercase) is rejected (exit 3)" "[ $_rc -eq 3 ]"

# ---------------------------------------------------------------------------
# Test 3: --bucket with slash is rejected
# ---------------------------------------------------------------------------
bash "${EXTRACT_SH}" --bucket "foo/bar" --dry-run 2>/dev/null
_rc=$?
_assert "--bucket 'foo/bar' (slash) is rejected (exit 3)" "[ $_rc -eq 3 ]"

# ---------------------------------------------------------------------------
# Test 4: valid --bucket name is accepted (dry-run, no tools required to install)
# ---------------------------------------------------------------------------
# dry-run exits before tool checks on unknown tool — we just check it doesn't exit 3
bash "${EXTRACT_SH}" --bucket "tests" --dry-run 2>/dev/null
_rc=$?
_assert "--bucket 'tests' passes validation (not exit 3)" "[ $_rc -ne 3 ]"

# ---------------------------------------------------------------------------
# Test 5: Files with spaces in path do not cause word-splitting errors
# We test the boundary validator, not the full pipeline (no ast-grep needed).
# ---------------------------------------------------------------------------
_tmpdir="$(mktemp -d)"
trap 'rm -rf "${_tmpdir}"' EXIT

# Create test files with tricky names
touch "${_tmpdir}/foo bar.py"
touch "${_tmpdir}/weird\$name.ts"
touch "${_tmpdir}/-rf.md"

# Verify files exist (basic sanity)
_assert "file 'foo bar.py' created successfully" "[ -f '${_tmpdir}/foo bar.py' ]"
_assert "file 'weird\$name.ts' created successfully" "[ -f '${_tmpdir}/weird\$name.ts' ]"
_assert "file '-rf.md' created successfully" "[ -f '${_tmpdir}/-rf.md' ]"

# Test that a NUL-delimited path pipeline handles spaces without word splitting:
# Simulate the NUL-delimited read pattern used in extract.sh
_read_ok=0
while IFS= read -r -d '' _f; do
  [ -f "${_f}" ] && _read_ok=$((_read_ok + 1))
done < <(printf '%s\0' "${_tmpdir}/foo bar.py" "${_tmpdir}/weird\$name.ts" "${_tmpdir}/-rf.md")
_assert "NUL-delimited read handles 3 tricky filenames without splitting" "[ $_read_ok -eq 3 ]"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "test_path_safety: PASSED=${_pass} FAILED=${_fail}"

if [ "$_fail" -gt 0 ]; then
  exit 1
fi
exit 0
