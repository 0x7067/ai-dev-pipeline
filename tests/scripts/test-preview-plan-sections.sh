#!/usr/bin/env bash
# Property + contract tests for scripts/preview-plan-sections.sh (A1).
#
# Covers acceptance criteria AC1, AC2, AC3, AC10, AC11 and invariants
# I2 (no STATUS: collision), I3 (≤60-line cap), I5 (fallback totality),
# I6 (idempotency on rendered output), I7 (no code execution).
#
# These tests are TDD-PRE: the helper does not yet exist; every assertion
# below MUST fail until the implementer lands the parser.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
HELPER="${REPO_ROOT}/scripts/preview-plan-sections.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if [ ! -x "$HELPER" ] && [ ! -f "$HELPER" ]; then
  fail "scripts/preview-plan-sections.sh missing (TDD-PRE: implementer has not landed it yet)"
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

run_helper() {
  # Helper contract: takes a plan path argument; prints preview to stdout;
  # exits 0; emits nothing on missing file (fail-closed).
  bash "$HELPER" "$1" 2>/dev/null
}

# --- Fixture A: plan with all four named sections ---
plan_full="$sandbox/plan-full.md"
cat > "$plan_full" <<'EOF'
# Plan

## Goal
Ship the thing.

## Risk Profile

- Risk tier: medium

## Risk rationale

Cross-module change.

## Acceptance Criteria

- [ ] AC1
- [ ] AC2

## Boundary Map

| Boundary | Direction |
|---|---|
| plan.md | ingress |

EOF

out_full=$(run_helper "$plan_full")
out_full_lines=$(printf '%s\n' "$out_full" | wc -l | tr -d ' ')

# AC1 / I3: hard 60-line cap.
if [ -n "$out_full" ] && [ "$out_full_lines" -le 60 ]; then
  pass "section-mode preview within 60-line cap (lines=$out_full_lines)"
else
  fail "section-mode preview missing or exceeds 60-line cap (lines=$out_full_lines)"
fi

# Section-mode must surface the four named headings verbatim.
for h in "Risk Tier" "Risk rationale" "Acceptance Criteria" "Boundary Map"; do
  if printf '%s\n' "$out_full" | grep -qF "$h"; then
    pass "section-mode preview includes heading '$h'"
  else
    fail "section-mode preview missing heading '$h'"
  fi
done

# I2 / AC10: no line begins with STATUS: at column 0.
if printf '%s\n' "$out_full" | grep -q '^STATUS:'; then
  fail "preview line begins with STATUS: (I2 violation)"
else
  pass "no preview line begins with STATUS: (I2)"
fi

# --- Fixture B: plan missing all four named headings → head-40 fallback ---
plan_nohead="$sandbox/plan-nohead.md"
{
  echo "# Plan"
  echo ""
  for i in $(seq 1 100); do echo "line $i body content"; done
} > "$plan_nohead"

out_fb=$(run_helper "$plan_nohead")
out_fb_lines=$(printf '%s\n' "$out_fb" | wc -l | tr -d ' ')

# AC2 / I5: fallback totality — must emit something, must be capped.
if [ -n "$out_fb" ] && [ "$out_fb_lines" -le 60 ]; then
  pass "head-fallback preview emitted and ≤60 lines (lines=$out_fb_lines)"
else
  fail "head-fallback preview missing or >60 lines (lines=$out_fb_lines)"
fi

# Head-40 fallback should include the early body text (line 1) but not
# line 100 (would prove cap was honored).
if printf '%s\n' "$out_fb" | grep -qF "line 1 body content"; then
  pass "head-fallback includes early body lines"
else
  fail "head-fallback missing early body content"
fi
if printf '%s\n' "$out_fb" | grep -qF "line 100 body content"; then
  fail "head-fallback exceeded cap (line 100 leaked into preview)"
else
  pass "head-fallback respected cap (line 100 not leaked)"
fi

# --- Fixture C: plan file missing → fail closed (no preview) ---
out_missing=$(run_helper "$sandbox/does-not-exist.md")
if [ -z "$out_missing" ]; then
  pass "AC3 fail-closed: missing plan emits nothing"
else
  fail "AC3 violated: missing plan emitted output: $out_missing"
fi

# --- Fixture D: adversarial Markdown — fenced code, $(...) , ANSI, control chars ---
plan_adv="$sandbox/plan-adv.md"
cat > "$plan_adv" <<'EOF'
# Plan

## Risk Tier

medium

## Risk rationale

```bash
$(rm -rf /)
`whoami`
${HOME}
```

## Acceptance Criteria

- AC: should not execute $(echo PWNED)

## Boundary Map

normal text
EOF
# Append an ANSI escape + a literal control char to the file.
printf 'after-ansi: \x1b[31mRED\x1b[0m end\n' >> "$plan_adv"
printf 'ctrlchar: A\x07B\n' >> "$plan_adv"

out_adv=$(run_helper "$plan_adv")

# I7 / AC11: substrings must appear as plain text OR be stripped, but
# NEVER executed. The literal token PWNED must not appear (would mean
# $(echo PWNED) was expanded). The literal token "rm -rf" SHOULD appear
# verbatim if rendered (proves we kept it as text, not eval'd).
if printf '%s\n' "$out_adv" | grep -q "PWNED"; then
  fail "I7 violation: \$(echo PWNED) was expanded in preview"
else
  pass "I7: \$() substitution not expanded"
fi

# Whoami output of the test runner must not appear (sanity).
who_now=$(whoami 2>/dev/null || echo "")
if [ -n "$who_now" ] && printf '%s\n' "$out_adv" | grep -qx "$who_now"; then
  fail "I7 violation: backtick whoami expanded to '$who_now'"
else
  pass "I7: backticks not expanded"
fi

# ANSI escape sequence must be stripped (R1 mitigation).
if printf '%s\n' "$out_adv" | grep -q $'\x1b\['; then
  fail "ANSI escape leaked into preview (R1 mitigation missing)"
else
  pass "ANSI escapes stripped"
fi

# BEL control char must be stripped.
if printf '%s\n' "$out_adv" | grep -q $'\x07'; then
  fail "BEL control char leaked into preview"
else
  pass "control characters stripped"
fi

# I2: no STATUS: line on adversarial input either.
if printf '%s\n' "$out_adv" | grep -q '^STATUS:'; then
  fail "adversarial preview emits STATUS: line (I2)"
else
  pass "adversarial preview has no STATUS: line"
fi

# --- Fixture E: 10k-line plan → must still be capped at 60 lines ---
plan_huge="$sandbox/plan-huge.md"
{
  echo "# Plan"
  echo "## Risk Tier"
  echo "medium"
  echo "## Risk rationale"
  for i in $(seq 1 10000); do echo "rationale line $i"; done
  echo "## Acceptance Criteria"
  echo "- AC1"
  echo "## Boundary Map"
  echo "none"
} > "$plan_huge"

out_huge=$(run_helper "$plan_huge")
out_huge_lines=$(printf '%s\n' "$out_huge" | wc -l | tr -d ' ')
if [ "$out_huge_lines" -le 60 ]; then
  pass "I3: 10k-line plan capped at 60 (got $out_huge_lines)"
else
  fail "I3 violation: 10k-line plan produced $out_huge_lines lines"
fi

# --- I6: idempotency on rendered output ---
# Re-feed the rendered preview as a "plan file" to the helper; output
# must be a fixed point (head-fallback of a head-fallback equals head-
# fallback, and section-mode of an already-bounded preview is stable).
rerun_input="$sandbox/rerun-input.md"
printf '%s\n' "$out_full" > "$rerun_input"
out_rerun=$(run_helper "$rerun_input")
out_rerun2_input="$sandbox/rerun-input2.md"
printf '%s\n' "$out_rerun" > "$out_rerun2_input"
out_rerun2=$(run_helper "$out_rerun2_input")
if [ "$out_rerun" = "$out_rerun2" ]; then
  pass "I6: idempotent on rendered preview (fixed point reached)"
else
  fail "I6 violation: re-parsing rendered preview is not stable"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-preview-plan-sections: FAILED ($failures)" >&2
  exit 1
fi
echo "test-preview-plan-sections: OK"
