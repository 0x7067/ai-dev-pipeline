#!/usr/bin/env bash
# Contract assertions for the command-surface consolidation.
#
# Verifies the post-consolidation invariants documented in
# docs/current-plan.md ("Acceptance Criteria") and docs/impl-summary.md:
#   - /ship exists with strict|adaptive mode dispatch
#   - /cycle and /autopilot are removed
#   - per-phase commands are demoted via "Advanced —" description prefix
#   - ops commands (setup, reset) are prefixed "Ops:"
#   - pragmatic-review-checklist skill is marked Internal
#   - no live (non-migration-note) references to /cycle or /autopilot
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

# 2. /cycle.md and /autopilot.md are absent
for stale in .claude/commands/cycle.md .claude/commands/autopilot.md; do
  if [ -e "$stale" ]; then
    fail "$stale should have been removed"
  else
    pass "$stale absent"
  fi
done

# 3. Per-phase commands carry "Advanced —" description prefix
for cmd in plan implement review test verify research; do
  f=".claude/commands/${cmd}.md"
  if [ ! -f "$f" ]; then
    fail "$f missing"
    continue
  fi
  # Look for description: line and confirm it starts with "Advanced —"
  desc=$(awk '/^description:/{sub(/^description:[[:space:]]*"?/,""); sub(/"?$/,""); print; exit}' "$f")
  case "$desc" in
    "Advanced —"*) pass "$f description prefixed Advanced —" ;;
    *)             fail "$f description does not start with 'Advanced —' (got: $desc)" ;;
  esac
done

# 4. /setup and /reset descriptions start with "Ops:"
for cmd in setup reset; do
  f=".claude/commands/${cmd}.md"
  if [ ! -f "$f" ]; then
    fail "$f missing"
    continue
  fi
  desc=$(awk '/^description:/{sub(/^description:[[:space:]]*"?/,""); sub(/"?$/,""); print; exit}' "$f")
  case "$desc" in
    "Ops:"*) pass "$f description prefixed Ops:" ;;
    *)       fail "$f description does not start with 'Ops:' (got: $desc)" ;;
  esac
done

# 5. pragmatic-review-checklist marked Internal
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

# 6. No live references to /cycle or /autopilot in skill/command/agent files.
# Migration notes inside CLAUDE.md and README.md are intentional and excluded.
live_hits=$(rg -n --no-heading -e '/cycle\b' -e '/autopilot\b' \
  .claude/commands .claude/skills .claude/agents 2>/dev/null || true)
if [ -n "$live_hits" ]; then
  fail "live /cycle or /autopilot references found in .claude/:"
  printf '%s\n' "$live_hits" >&2
else
  pass "no live /cycle or /autopilot references in .claude/{commands,skills,agents}"
fi

# Sanity: README.md and CLAUDE.md references should be migration notes only.
for doc in README.md CLAUDE.md; do
  hits=$(rg -n --no-heading -e '/cycle\b' -e '/autopilot\b' "$doc" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    # Each hit must contain the word "Migration" or "Replaces" or "previous"
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
