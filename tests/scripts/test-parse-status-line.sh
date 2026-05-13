#!/usr/bin/env bash
# Contract + property tests for scripts/parse-status-line.sh.
#
# Boundary parser tests per .claude/rules/boundary-parse-dont-validate.md:
#   - accept corpus: every canonical-shaped STATUS line parses
#   - reject corpus: every malformed line is rejected (fail-closed)
#   - backward-compat: missing risk_reason → "(unspecified)"
#   - property fuzz: random STATUS-shaped lines round-trip the report path

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-status-line.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

# --- accept corpus ---
declare -a accept_lines=(
  'STATUS: ok | risk=low | summary | report=docs/x.md'
  'STATUS: ok | risk=medium | risk_reason=cross-module change | sum | report=docs/y.md'
  'STATUS: go | summary | report=docs/r.md'
  'STATUS: blocked | risk=unknown | template missing | report=none'
  'STATUS: ok | blocking=0 | review summary | report=docs/review.md'
  'STATUS: ok | risk=high | risk_reason=auth/authz change | report=p.md'
  'STATUS: queued | risk=medium | pending approval | report=docs/p.md'
  'STATUS: no-go | gate failed | report=docs/v.md'
)
for line in "${accept_lines[@]}"; do
  out="$(bash "$PARSER" "$line" 2>/dev/null)" || { fail "accept rejected: $line"; continue; }
  echo "$out" | grep -q '^status=' || { fail "no status= for: $line"; continue; }
  echo "$out" | grep -q '^report=' || { fail "no report= for: $line"; continue; }
  pass "accept: $line"
done

# --- backward compat: missing risk_reason → (unspecified) ---
out="$(bash "$PARSER" 'STATUS: ok | risk=low | x | report=p.md')"
echo "$out" | grep -q '^risk_reason=(unspecified)$' \
  && pass "missing risk_reason defaulted" \
  || fail "missing risk_reason default broken: $out"

# --- reject corpus ---
declare -a reject_lines=(
  ''
  'no status prefix here'
  'STATUS:'
  'STATUS: ok'
  'STATUS: ok | summary'                       # missing report=
  'STATUS: invalid | x | report=p.md'          # bad verb
  'STATUS: ok | risk=critical | x | report=p.md'  # bad risk
  $'STATUS: ok | x | report=\x1bp.md'          # ANSI escape
)
for line in "${reject_lines[@]}"; do
  if bash "$PARSER" "$line" >/dev/null 2>&1; then
    fail "reject accepted: $line"
  else
    pass "reject: $(printf '%q' "$line")"
  fi
done

# --- property: random reports round-trip ---
i=0
while [ "$i" -lt 50 ]; do
  hex=$(printf '%04x' $((RANDOM % 65536)))
  rep="docs/aidp/runs/${hex}/r.md"
  line="STATUS: ok | risk=low | s$i | report=$rep"
  out="$(bash "$PARSER" "$line" 2>/dev/null)" || { fail "fuzz reject: $line"; i=$((i+1)); continue; }
  parsed_rep="$(echo "$out" | sed -n 's/^report=//p')"
  [ "$parsed_rep" = "$rep" ] || fail "round-trip fail: $rep != $parsed_rep"
  i=$((i+1))
done
pass "property: 50 round-trips"

# --- stdin variant ---
out="$(printf 'STATUS: ok | risk=low | s | report=p.md\n' | bash "$PARSER")"
echo "$out" | grep -q '^status=ok$' && pass "stdin accept" || fail "stdin accept failed"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures" >&2
  exit 1
fi
echo "OK"
