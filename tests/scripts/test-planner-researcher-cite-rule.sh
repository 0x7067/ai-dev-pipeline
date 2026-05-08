#!/usr/bin/env bash
# Asserts that planner.md and researcher.md explicitly reference the
# decision-surfacing rule in their <constraints> section.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLANNER="$REPO_ROOT/.claude/agents/planner.md"
RESEARCHER="$REPO_ROOT/.claude/agents/researcher.md"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

assert_cites() {
  local file=$1 label=$2
  if [ ! -f "$file" ]; then
    fail "$label: file missing ($file)"
    return
  fi
  if grep -q '\.claude/rules/decision-surfacing\.md' "$file"; then
    pass "$label cites decision-surfacing.md"
  else
    fail "$label does not cite .claude/rules/decision-surfacing.md"
  fi
}

# Constraints-section locality: extract the <constraints>...</constraints>
# block and confirm the citation lives there (not just somewhere in the file).
assert_in_constraints() {
  local file=$1 label=$2
  local block
  block=$(awk '/<constraints>/,/<\/constraints>/' "$file")
  if printf '%s\n' "$block" | grep -q '\.claude/rules/decision-surfacing\.md'; then
    pass "$label cites the rule inside <constraints>"
  else
    fail "$label citation is not inside <constraints>"
  fi
}

assert_cites "$PLANNER" "planner.md"
assert_in_constraints "$PLANNER" "planner.md"
assert_cites "$RESEARCHER" "researcher.md"
assert_in_constraints "$RESEARCHER" "researcher.md"

if [ "$fail_count" -gt 0 ]; then
  printf '\n%d assertion(s) failed\n' "$fail_count" >&2
  exit 1
fi
printf '\nall assertions passed\n'
