#!/usr/bin/env bash
# Verifies _hook_lib.sh::compact_tool_output groups ESLint / tsc / ruff
# style output by (file, rule) when the input exceeds HOOK_OUTPUT_MAX_LINES,
# and passes input through unchanged when it does not.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO_ROOT/.claude/hooks/_hook_lib.sh"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

# Source the lib in utility-only mode so it does not consume stdin.
# shellcheck disable=SC1090
HOOK_NAME="test-compact" HOOK_LIB_NO_STDIN=1 source "$LIB"

# --- short input passes through unchanged ---
short_in="$(printf 'line one\nline two\nline three\n')"
short_out="$(printf '%s\n' "$short_in" | HOOK_OUTPUT_MAX_LINES=30 compact_tool_output)"
if [ "$short_out" = "$short_in" ]; then
  pass "short input passes through unchanged"
else
  fail "short input mutated: $short_out"
fi

# --- ESLint stylish: 8 unbound-method errors → grouped ---
eslint_in="$(cat <<'EOF'

/repo/apps/api/src/jobs/provision-worker.test.ts
  182:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  198:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  199:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  216:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  229:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  246:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  264:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method
  297:5  error  Avoid referencing unbound methods   @typescript-eslint/unbound-method

✖ 8 problems (8 errors, 0 warnings)

ESLint found too many problems
context noise 1
context noise 2
context noise 3
context noise 4
context noise 5
context noise 6
context noise 7
context noise 8
context noise 9
context noise 10
context noise 11
context noise 12
context noise 13
context noise 14
context noise 15
context noise 16
context noise 17
context noise 18
context noise 19
context noise 20
context noise 21
context noise 22
context noise 23
EOF
)"
eslint_out="$(printf '%s\n' "$eslint_in" | HOOK_OUTPUT_MAX_LINES=20 compact_tool_output)"
if printf '%s' "$eslint_out" | grep -q '@typescript-eslint/unbound-method × 8'; then
  pass "ESLint: groups 8 unbound-method into one × 8 line"
else
  fail "ESLint: expected '× 8' grouping; got:
$eslint_out"
fi
if printf '%s' "$eslint_out" | grep -q 'lines 182,198,199,216,229,246,264,297'; then
  pass "ESLint: emits ordered line list"
else
  fail "ESLint: missing line list; got:
$eslint_out"
fi
# Compaction should be shorter than input
in_lines=$(printf '%s\n' "$eslint_in" | wc -l | tr -d ' ')
out_lines=$(printf '%s\n' "$eslint_out" | wc -l | tr -d ' ')
if [ "$out_lines" -lt "$in_lines" ]; then
  pass "ESLint: output ($out_lines lines) shorter than input ($in_lines lines)"
else
  fail "ESLint: output not compacted ($out_lines >= $in_lines)"
fi

# --- tsc: multiple TS2322 in same file → grouped ---
tsc_in="$(cat <<'EOF'
src/foo.ts(10,5): error TS2322: Type 'string' is not assignable to type 'number'.
src/foo.ts(20,5): error TS2322: Type 'string' is not assignable to type 'number'.
src/foo.ts(30,5): error TS2322: Type 'string' is not assignable to type 'number'.
src/bar.ts(15,1): error TS2304: Cannot find name 'foo'.
filler 1
filler 2
filler 3
filler 4
filler 5
filler 6
filler 7
filler 8
filler 9
filler 10
filler 11
filler 12
filler 13
filler 14
filler 15
filler 16
filler 17
filler 18
filler 19
filler 20
filler 21
filler 22
filler 23
filler 24
filler 25
filler 26
filler 27
filler 28
EOF
)"
tsc_out="$(printf '%s\n' "$tsc_in" | HOOK_OUTPUT_MAX_LINES=20 compact_tool_output)"
if printf '%s' "$tsc_out" | grep -q 'TS2322 × 3'; then
  pass "tsc: groups 3× TS2322 in one file"
else
  fail "tsc: missing TS2322 × 3 grouping; got:
$tsc_out"
fi
if printf '%s' "$tsc_out" | grep -q 'TS2304 × 1'; then
  pass "tsc: counts singleton TS2304"
else
  fail "tsc: missing TS2304 × 1; got:
$tsc_out"
fi

# --- ruff: multiple E501 → grouped ---
ruff_in="$(cat <<'EOF'
src/a.py:10:101: E501 line too long (110 > 100)
src/a.py:22:101: E501 line too long (105 > 100)
src/a.py:30:101: E501 line too long (120 > 100)
src/a.py:42:1: F401 'os' imported but unused
filler 1
filler 2
filler 3
filler 4
filler 5
filler 6
filler 7
filler 8
filler 9
filler 10
filler 11
filler 12
filler 13
filler 14
filler 15
filler 16
filler 17
filler 18
filler 19
filler 20
filler 21
filler 22
filler 23
filler 24
filler 25
filler 26
filler 27
filler 28
filler 29
filler 30
EOF
)"
ruff_out="$(printf '%s\n' "$ruff_in" | HOOK_OUTPUT_MAX_LINES=20 compact_tool_output)"
if printf '%s' "$ruff_out" | grep -q 'E501 × 3'; then
  pass "ruff: groups 3× E501"
else
  fail "ruff: missing E501 × 3 grouping; got:
$ruff_out"
fi

# --- disable switch: HOOK_OUTPUT_COMPACT=0 → passthrough ---
disabled_out="$(printf '%s\n' "$eslint_in" | HOOK_OUTPUT_COMPACT=0 HOOK_OUTPUT_MAX_LINES=5 compact_tool_output)"
if [ "$disabled_out" = "$eslint_in" ]; then
  pass "HOOK_OUTPUT_COMPACT=0 disables compaction"
else
  fail "HOOK_OUTPUT_COMPACT=0 did not passthrough"
fi

# --- no recognised pattern → passthrough (head + tail count) ---
unknown_in="$(yes 'some random output line' | head -n 50)"
unknown_out="$(printf '%s\n' "$unknown_in" | HOOK_OUTPUT_MAX_LINES=20 compact_tool_output)"
# Falls through to passthrough since no pattern matched (matched=0).
if [ "$(printf '%s' "$unknown_out" | wc -l | tr -d ' ')" = "$(printf '%s' "$unknown_in" | wc -l | tr -d ' ')" ]; then
  pass "unrecognised input passes through unchanged"
else
  fail "unrecognised input mutated"
fi

if [ "$fail_count" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail_count"
  exit 1
fi
printf '\nall assertions passed\n'
