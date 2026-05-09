#!/usr/bin/env bash
# AC7: Plan template renders ≤30 lines for risk=low runs; Non-Goals,
# Boundary Parsers, FC/IS Classification, Invariants, Failure Modes
# sections are absent (or marked Optional).
#
# Strategy: inspect the canonical template in
# docs/templates/current-plan-template.md. The post-simplification template
# MUST mark the listed sections as Optional via HTML comments, and MUST
# document a risk-low cap.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
TEMPLATE="${REPO_ROOT}/docs/templates/current-plan-template.md"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$TEMPLATE" ] || { echo "template missing at $TEMPLATE" >&2; exit 2; }

# Each of these h2 sections must be marked Optional / "omit for risk=low" via
# a nearby HTML comment. We grep for the canonical optional marker anchored
# to each heading.
optional_sections=(
  "Non-Goals"
  "Boundary Parsers"
  "FC/IS Classification"
  "Invariants"
  "Failure Modes"
)

for sect in "${optional_sections[@]}"; do
  # Look for the section heading and a nearby HTML comment containing "Optional"
  # within ±3 lines. Use awk for proximity matching.
  if awk -v s="$sect" '
      $0 ~ "^## " s { hit=NR }
      hit && NR<=hit+3 && /<!--/ && /[Oo]ptional/ && /risk=low/ { found=1; exit }
      END { exit (found?0:1) }
    ' "$TEMPLATE"; then
    pass "section '$sect' marked Optional (omit for risk=low)"
  else
    fail "section '$sect' not marked Optional/omit-for-risk=low (AC7)"
  fi
done

# A canonical-shape note for risk=low cap should be present somewhere.
if grep -qE 'risk[- ]low.*(≤[[:space:]]*30|<=[[:space:]]*30|30[- ]line)' "$TEMPLATE"; then
  pass "template documents risk=low ≤30-line cap"
else
  fail "template does not document the ≤30-line risk-low cap (AC7)"
fi

# change-class field promoted (front-matter or risk profile)
if grep -qE 'change[- ]class' "$TEMPLATE"; then
  pass "change-class field documented in template"
else
  fail "change-class field not documented in template (AC7/AC10)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac7-risk-low-template-shape: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac7-risk-low-template-shape: OK"
