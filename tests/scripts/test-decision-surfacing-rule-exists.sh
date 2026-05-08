#!/usr/bin/env bash
# Asserts the decision-surfacing rule exists, has required sections, and is
# wired into CLAUDE.md's @-list.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RULE="$REPO_ROOT/.claude/rules/decision-surfacing.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if [ ! -f "$RULE" ]; then
  fail "decision-surfacing.md does not exist at $RULE"
  exit 1
fi
pass "rule file exists"

assert_grep() {
  local pattern=$1 label=$2
  if grep -qE "$pattern" "$RULE"; then
    pass "$label"
  else
    fail "$label (pattern: $pattern)"
  fi
}

assert_grep '^## Meaningful \(must ask\)' 'Meaningful (must ask) section present'
assert_grep '^## Trivial \(don'"'"'t ask\)' 'Trivial (don'"'"'t ask) section present'
assert_grep 'Ambiguous' 'Ambiguous-case clause present'
assert_grep '\(Recommended\)' '(Recommended) option-#1 convention present'
assert_grep 'DURING planning/research' 'Timing requirement present'
assert_grep 'BEFORE' 'Timing requirement uses BEFORE language'

# Wiring: CLAUDE.md @-list must reference the rule
if grep -qE '^@\.claude/rules/decision-surfacing\.md$' "$CLAUDE_MD"; then
  pass "CLAUDE.md @-list references the rule"
else
  fail "CLAUDE.md @-list does not reference @.claude/rules/decision-surfacing.md"
fi

if [ "$fail_count" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail_count" >&2
  exit 1
fi
printf '\nall assertions passed\n'
