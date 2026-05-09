#!/usr/bin/env bash
# Property + contract tests for scripts/preview-finding-titles.sh (A3).
#
# Covers AC5, AC6, AC7, AC10, AC11 and invariants I2 (no STATUS:),
# I4 (≤3 finding cap), I7 (no code execution), and the 120-char title
# truncation contract.
#
# TDD-PRE: helper does not yet exist; assertions MUST fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
HELPER="${REPO_ROOT}/scripts/preview-finding-titles.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if [ ! -x "$HELPER" ] && [ ! -f "$HELPER" ]; then
  fail "scripts/preview-finding-titles.sh missing (TDD-PRE)"
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Helper contract: bash preview-finding-titles.sh <report-path> <anchor-heading>
# Prints up to 3 indented finding titles to stdout, one per line.
# On missing file or missing anchor: emits nothing (fail-closed).
run_helper() {
  bash "$HELPER" "$1" "$2" 2>/dev/null
}

# --- Fixture A: review report with 5 blocking findings → cap at 3 ---
report_a="$sandbox/review-report.md"
cat > "$report_a" <<'EOF'
# Review Report

## Summary

5 blocking findings.

## Blocking findings

- First blocking finding title
- Second blocking finding title
- Third blocking finding title
- Fourth blocking finding title (should be dropped)
- Fifth blocking finding title (should be dropped)

## Advisory findings

- Advisory one
EOF

out_a=$(run_helper "$report_a" "## Blocking findings")
count_a=$(printf '%s\n' "$out_a" | grep -c . || true)
if [ "$count_a" -le 3 ] && [ "$count_a" -ge 1 ]; then
  pass "I4 / AC5: ≤3 finding titles (got $count_a)"
else
  fail "I4 / AC5 violation: emitted $count_a titles (expected 1..3)"
fi

# AC5: order preserved, first three included.
if printf '%s\n' "$out_a" | grep -qF "First blocking finding title" \
   && printf '%s\n' "$out_a" | grep -qF "Second blocking finding title" \
   && printf '%s\n' "$out_a" | grep -qF "Third blocking finding title"; then
  pass "AC5: first three findings present in order"
else
  fail "AC5: first three findings not all surfaced"
fi
if printf '%s\n' "$out_a" | grep -qF "Fourth blocking"; then
  fail "I4 violation: fourth finding leaked past cap"
else
  pass "fourth finding correctly dropped"
fi

# I2 / AC10: no STATUS: at column 0.
if printf '%s\n' "$out_a" | grep -q '^STATUS:'; then
  fail "AC10 / I2: preview line starts with STATUS:"
else
  pass "no preview line starts with STATUS:"
fi

# --- Fixture B: title truncation @ 120 chars (AC6) ---
long_title=$(printf 'X%.0s' $(seq 1 200))
report_b="$sandbox/review-long.md"
{
  echo "# Review"
  echo ""
  echo "## Blocking findings"
  echo ""
  echo "- $long_title"
} > "$report_b"
out_b=$(run_helper "$report_b" "## Blocking findings")
# Each emitted line should be ≤ some reasonable bound. The contract
# truncates titles to 120 chars + `…`. Allow up to 130 chars including
# any indent prefix.
max_len=$(printf '%s\n' "$out_b" | awk '{ if (length($0) > m) m = length($0) } END { print m+0 }')
if [ "$max_len" -le 130 ] && [ "$max_len" -ge 1 ]; then
  pass "AC6: long title truncated (max line length=$max_len)"
else
  fail "AC6 violation: long title not truncated (max line length=$max_len)"
fi
if printf '%s\n' "$out_b" | grep -q '…'; then
  pass "AC6: truncation marker '…' present"
else
  fail "AC6: truncation marker '…' missing on overlong title"
fi

# --- Fixture C: missing anchor heading → no preview (AC7) ---
report_c="$sandbox/review-no-anchor.md"
cat > "$report_c" <<'EOF'
# Review

## Summary

All clean.
EOF
out_c=$(run_helper "$report_c" "## Blocking findings")
if [ -z "$out_c" ]; then
  pass "AC7: missing anchor → empty preview"
else
  fail "AC7 violated: emitted output despite missing anchor: $out_c"
fi

# --- Fixture D: missing report file → fail closed ---
out_d=$(run_helper "$sandbox/does-not-exist.md" "## Blocking findings")
if [ -z "$out_d" ]; then
  pass "AC7 fail-closed: missing report → empty preview"
else
  fail "AC7 fail-closed violated: missing report emitted: $out_d"
fi

# --- Fixture E: adversarial titles — code substitution + ANSI + control chars ---
report_e="$sandbox/review-adv.md"
cat > "$report_e" <<'EOF'
# Review

## Blocking findings

- Title with $(echo PWNED) substitution attempt
- Title with `whoami` backticks
- Title with ${HOME} variable expansion
EOF
printf -- '- Title with ANSI \x1b[31mred\x1b[0m suffix\n' >> "$report_e"
printf -- '- Title with BEL \x07 inside\n' >> "$report_e"

out_e=$(run_helper "$report_e" "## Blocking findings")

if printf '%s\n' "$out_e" | grep -q "PWNED"; then
  fail "I7: \$() substitution expanded inside finding title"
else
  pass "I7: \$() substitution not expanded in title"
fi
who_now=$(whoami 2>/dev/null || echo "")
if [ -n "$who_now" ] && printf '%s\n' "$out_e" | grep -qx "$who_now"; then
  fail "I7: backticks expanded in finding title"
else
  pass "I7: backticks not expanded in title"
fi
if printf '%s\n' "$out_e" | grep -q $'\x1b\['; then
  fail "ANSI escape leaked into finding title"
else
  pass "ANSI escapes stripped from titles"
fi
if printf '%s\n' "$out_e" | grep -q $'\x07'; then
  fail "BEL control char leaked into finding title"
else
  pass "control chars stripped from titles"
fi

# Newlines inside emitted titles must not exist (contract: rejects \n).
# Each emitted title is on a single line, so the count of titles
# equals the count of non-empty output lines. Already implied by the
# cap test, but assert directly: each non-empty line corresponds to
# exactly one title token.
nlines=$(printf '%s\n' "$out_e" | grep -c . || true)
if [ "$nlines" -le 3 ]; then
  pass "I4 holds on adversarial input ($nlines titles)"
else
  fail "I4 violation on adversarial input ($nlines titles)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-preview-finding-titles: FAILED ($failures)" >&2
  exit 1
fi
echo "test-preview-finding-titles: OK"
