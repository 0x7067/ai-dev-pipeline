#!/usr/bin/env bash
# AC3: implementer/tester/verifier/auditor have prose enumerating Bash command
# shapes; verifier additionally restricted to gate runner + git status/diff +
# read-only inspection (no sed -i etc).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

for agent in implementer tester verifier auditor; do
  F="$REPO_ROOT/.claude/agents/$agent.md"
  # Look for a prose section discussing Bash usage / command shapes.
  if grep -qiE '(bash[- ]usage|bash[- ]scope|bash[- ]commands|allowed bash|bash command shapes|intended bash)' "$F"; then
    pass "$agent.md contains Bash scoping prose"
  else
    fail "$agent.md missing Bash scoping prose"
  fi
done

V="$REPO_ROOT/.claude/agents/verifier.md"
if grep -qF 'scripts/run-verification-gates.sh' "$V"; then
  pass "verifier.md prose names run-verification-gates.sh"
else
  fail "verifier.md prose missing run-verification-gates.sh"
fi
if grep -qE 'git status' "$V" && grep -qE 'git diff' "$V"; then
  pass "verifier.md prose names git status / git diff"
else
  fail "verifier.md prose missing git status / git diff"
fi
# Forbid sed -i in verifier prose (write-via-shell anti-pattern).
if grep -qE 'sed -i' "$V"; then
  # Only fail if NOT clearly inside a "must not" / "no" clause.
  if grep -qE '(no |not allowed|forbidden|must not).{0,40}sed -i' "$V"; then
    pass "verifier.md mentions sed -i only as forbidden"
  else
    fail "verifier.md mentions sed -i without forbidding it"
  fi
else
  pass "verifier.md does not mention sed -i"
fi

if [ "$fail_count" -gt 0 ]; then exit 1; fi
printf '\nall assertions passed\n'
