#!/usr/bin/env bash
# Contract assertions for the 5-command primary surface.
#
# Verifies the post-reduction invariants documented in
# docs/current-plan.md ("Acceptance Criteria") and docs/impl-summary.md:
#   - .claude/commands/ contains exactly the 5 primary commands
#   - the 6 deleted per-phase/ops commands are absent
#   - /ship retains strict|adaptive mode dispatch
#   - pragmatic-review-checklist skill is marked Internal
#   - /cycle and /autopilot remain absent
#   - no live (non-migration-note) references to /cycle, /autopilot, or any
#     deleted slash command in .claude/{commands,skills,agents}
#
# Exit 0 on success, 1 on any failed assertion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

rc=0
fail() { echo "command-surface: FAIL: $*" >&2; rc=1; }
pass() { echo "command-surface: ok: $*"; }

# 1. /ship exists and contains strict|adaptive mode dispatch
ship=.claude/commands/ship.md
if [ ! -f "$ship" ]; then
  fail "$ship missing"
else
  if ! grep -q 'mode=strict' "$ship" || ! grep -q 'mode=adaptive' "$ship"; then
    fail "$ship missing strict|adaptive mode dispatch"
  else
    pass "ship.md present with strict|adaptive dispatch"
  fi
fi

# 2. /cycle.md, /autopilot.md, and the 6 deleted per-phase/ops commands are absent.
for stale in \
    .claude/commands/cycle.md \
    .claude/commands/autopilot.md \
    .claude/commands/plan.md \
    .claude/commands/implement.md \
    .claude/commands/test.md \
    .claude/commands/verify.md \
    .claude/commands/setup.md \
    .claude/commands/reset.md; do
  if [ -e "$stale" ]; then
    fail "$stale should have been removed"
  else
    pass "$stale absent"
  fi
done

# 3. The 5 primary commands are present, and ONLY those 5.
expected_cmds=(ship review refactor audit research)
for cmd in "${expected_cmds[@]}"; do
  f=".claude/commands/${cmd}.md"
  if [ ! -f "$f" ]; then
    fail "$f missing"
  else
    pass "$f present"
  fi
done

# Count actual *.md files under .claude/commands/ and confirm = 5.
actual_count=$(find .claude/commands -maxdepth 1 -type f -name '*.md' | wc -l | tr -d '[:space:]')
if [ "$actual_count" != "5" ]; then
  fail ".claude/commands contains $actual_count *.md files, expected exactly 5"
  find .claude/commands -maxdepth 1 -type f -name '*.md' >&2
else
  pass ".claude/commands contains exactly 5 *.md files"
fi

# 4. pragmatic-review-checklist marked Internal
prc=.claude/skills/pragmatic-review-checklist/SKILL.md
if [ ! -f "$prc" ]; then
  fail "$prc missing"
else
  if grep -E '^description:' "$prc" | grep -q 'Internal'; then
    pass "pragmatic-review-checklist marked Internal"
  else
    fail "pragmatic-review-checklist description does not mark it Internal"
  fi
fi

# 5. No live re-dispatch references to /cycle, /autopilot, or any deleted
#    slash command in .claude/{commands,skills}. Agent files (.claude/agents)
#    use slash-prefixed phase names as frontmatter metadata (`runs-after:`,
#    `consumed-by:`, etc.) — those are documentation, not live dispatch, and
#    agent prompts are out of scope per the approved plan.
live_hits=$(rg -n --no-heading \
  -e '/cycle\b' \
  -e '/autopilot\b' \
  -e '(^|[^a-zA-Z])/plan\b' \
  -e '(^|[^a-zA-Z])/implement\b' \
  -e '(^|[^a-zA-Z])/test\b' \
  -e '(^|[^a-zA-Z])/verify\b' \
  -e '(^|[^a-zA-Z])/setup\b' \
  -e '(^|[^a-zA-Z])/reset\b' \
  .claude/commands .claude/skills 2>/dev/null || true)
# Filter out path-like matches (e.g. "scripts/run-verification-gates.sh") and
# the deleted-command path references inside this script's own comments.
filtered=$(printf '%s\n' "$live_hits" | awk '
  NF == 0 { next }
  # Drop lines where any slash token is part of a longer path segment
  /\/(plan|implement|test|verify|setup|reset|cycle|autopilot)\// { next }
  { print }
')
if [ -n "$filtered" ]; then
  fail "live deleted-slash-command references found in .claude/:"
  printf '%s\n' "$filtered" >&2
else
  pass "no live deleted-slash-command references in .claude/{commands,skills,agents}"
fi

# Sanity: README.md and CLAUDE.md references to /cycle|/autopilot must remain
# migration notes only.
for doc in README.md CLAUDE.md; do
  hits=$(rg -n --no-heading -e '/cycle\b' -e '/autopilot\b' "$doc" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    while IFS= read -r line; do
      case "$line" in
        *Migration*|*Replaces*|*previous*) ;;
        *) fail "$doc: non-migration-note reference: $line" ;;
      esac
    done <<<"$hits"
    pass "$doc references to /cycle|/autopilot are migration notes"
  fi
done

if [ "$rc" -ne 0 ]; then
  echo "command-surface: FAILED" >&2
  exit 1
fi

echo "command-surface: OK"
