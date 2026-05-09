#!/usr/bin/env bash
# Contract test for the size-hint formatter (A4 / AC8).
#
# The plan documents a pure `format_size_hint(n_lines: int) -> str` that
# renders `(N lines)`. In bash form, the implementer is expected to
# expose this as either:
#   (a) a function `format_size_hint` sourced from a library file
#       (e.g. scripts/lib/format-size-hint.sh), OR
#   (b) a tiny helper script `scripts/format-size-hint.sh <n>` that
#       prints the rendered hint to stdout.
#
# This test accepts EITHER shape so the implementer keeps freedom; both
# absent → fail.
#
# TDD-PRE: neither shape exists yet.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

LIB="${REPO_ROOT}/scripts/lib/format-size-hint.sh"
HELPER="${REPO_ROOT}/scripts/format-size-hint.sh"

render() {
  # $1 = line count
  if [ -f "$LIB" ]; then
    # shellcheck disable=SC1090
    ( . "$LIB" && format_size_hint "$1" )
  elif [ -f "$HELPER" ]; then
    bash "$HELPER" "$1"
  else
    return 2
  fi
}

if [ ! -f "$LIB" ] && [ ! -f "$HELPER" ]; then
  fail "neither scripts/lib/format-size-hint.sh nor scripts/format-size-hint.sh exists (TDD-PRE)"
fi

# --- Contract: render shape is exactly `(N lines)` ---
for n in 0 1 2 7 42 1000; do
  out=$(render "$n" 2>/dev/null || echo "__ERR__")
  expected="($n lines)"
  if [ "$out" = "$expected" ]; then
    pass "format_size_hint($n) = '$expected'"
  else
    fail "format_size_hint($n): expected '$expected', got '$out'"
  fi
done

# --- Property: idempotent shape — calling twice with the same n yields equal output ---
a=$(render 17 2>/dev/null || echo "")
b=$(render 17 2>/dev/null || echo "")
if [ "$a" = "$b" ] && [ -n "$a" ]; then
  pass "deterministic: format_size_hint(17) is stable"
else
  fail "non-deterministic or empty output: a='$a' b='$b'"
fi

# --- Property: never starts with STATUS: (I2) ---
if printf '%s\n' "$a" | grep -q '^STATUS:'; then
  fail "I2 violation: size hint starts with STATUS:"
else
  pass "I2: size hint does not start with STATUS:"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-format-size-hint: FAILED ($failures)" >&2
  exit 1
fi
echo "test-format-size-hint: OK"
