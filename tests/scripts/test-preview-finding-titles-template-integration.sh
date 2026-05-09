#!/usr/bin/env bash
# Integration test: scripts/preview-finding-titles.sh against
# template-shaped report headings (the actual review-report-template.md,
# verify-report-template.md, audit-report-template.md headings).
#
# Regression coverage for the A3 anchor-mismatch blocker — the helper's
# anchor matcher must succeed on real heading shapes, not only on
# synthetic fixtures whose headings are byte-identical to the anchor.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
HELPER="${REPO_ROOT}/scripts/preview-finding-titles.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

if [ ! -f "$HELPER" ]; then
  fail "helper missing: $HELPER"
  echo "test-preview-finding-titles-template-integration: FAILED ($failures)" >&2
  exit 1
fi

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# --- Review template shape: heading is "## Blocking Findings (Tool-Derived)" ---
review_report="$sandbox/review-report.md"
cat > "$review_report" <<'EOF'
# Review Report

## Findings (Highest Severity First)

## Blocking Findings (Tool-Derived)

- Real-world blocking title alpha
- Real-world blocking title beta

## Advisory Findings (Model)

- Real-world advisory title gamma
EOF

out=$(bash "$HELPER" "$review_report" "## Blocking findings" 2>/dev/null)
if printf '%s\n' "$out" | grep -qF "Real-world blocking title alpha"; then
  pass "review template: '## Blocking findings' matches '## Blocking Findings (Tool-Derived)'"
else
  fail "review template: anchor did not match real heading shape (got: $out)"
fi
out=$(bash "$HELPER" "$review_report" "## Advisory findings" 2>/dev/null)
if printf '%s\n' "$out" | grep -qF "Real-world advisory title gamma"; then
  pass "review template: '## Advisory findings' matches '## Advisory Findings (Model)'"
else
  fail "review template: advisory anchor did not match real heading shape"
fi

# --- Verify template shape: heading is "## Gate Results" with numbered items ---
verify_report="$sandbox/verify-report.md"
cat > "$verify_report" <<'EOF'
# Verify Report

## Context
- Risk tier: medium

## Gate Results
- Type/compile: failed (exit 1)
- Lint: failed (exit 2)
- Property tests: failed
EOF

out=$(bash "$HELPER" "$verify_report" "## Gate Results" 2>/dev/null)
nlines=$(printf '%s\n' "$out" | grep -c . || true)
if [ "$nlines" -ge 1 ]; then
  pass "verify template: '## Gate Results' anchor extracts at least one entry ($nlines)"
else
  fail "verify template: '## Gate Results' anchor extracted nothing"
fi

# --- Audit template shape: heading is "## 2. Critical or Urgent Issues" ---
audit_report="$sandbox/audit-report.md"
cat > "$audit_report" <<'EOF'
# Audit Report

## 1. Overall Structure and Conventions

Some prose.

## 2. Critical or Urgent Issues

- Critical title one
- Critical title two

## 3. Improvement Suggestions (Non-Urgent)

- Improvement title alpha
EOF

out=$(bash "$HELPER" "$audit_report" "## Critical or Urgent Issues" 2>/dev/null)
if printf '%s\n' "$out" | grep -qF "Critical title one"; then
  pass "audit template: '## Critical or Urgent Issues' matches '## 2. Critical or Urgent Issues' (numeric-prefix strip)"
else
  fail "audit template: numeric-prefix-stripped anchor failed (got: $out)"
fi
out=$(bash "$HELPER" "$audit_report" "## Improvement Suggestions" 2>/dev/null)
if printf '%s\n' "$out" | grep -qF "Improvement title alpha"; then
  pass "audit template: '## Improvement Suggestions' matches '## 3. Improvement Suggestions (Non-Urgent)'"
else
  fail "audit template: improvement anchor failed"
fi

# --- Case insensitivity sanity check ---
out=$(bash "$HELPER" "$review_report" "## blocking FINDINGS" 2>/dev/null)
if printf '%s\n' "$out" | grep -qF "Real-world blocking title alpha"; then
  pass "case-insensitive prefix match works"
else
  fail "case-insensitive match failed"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-preview-finding-titles-template-integration: FAILED ($failures)" >&2
  exit 1
fi
echo "test-preview-finding-titles-template-integration: OK"
