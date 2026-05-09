#!/usr/bin/env bash
# Property tests for scripts/lib/decisions-core.sh.
#
# Covers HITL plan invariants:
#   I3 round-trip: parse(build(x)) == x for every DecisionRecord
#   I4 time injection: same inputs (incl. ts) → same record
#   "no ANSI": rejected at build time

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
LIB="${REPO_ROOT}/scripts/lib/decisions-core.sh"

[ -f "$LIB" ] || { echo "lib missing at $LIB" >&2; exit 2; }
# shellcheck source=/dev/null
source "$LIB"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# --- accept corpus ---
declare -a cases=(
  '2026-05-09T10:00:00Z|user|plan|approve|risk acceptable|abc123'
  '2026-05-09T10:00:00Z|auto|release|approve|all gates green|'
  '2026-05-09T10:00:00Z|user|plan|edit|tighten retry policy|abc123'
  '2026-05-09T10:00:00Z|user|plan|reject|out of scope|'
  '2026-05-09T10:00:00Z|time-box|plan|reject|elapsed|abc123'
  '2026-05-09T10:00:00Z|user|refactor-plan|approve|scope above threshold|'
)
for c in "${cases[@]}"; do
  IFS='|' read -r ts actor gate verb rat hash <<<"$c"
  line="$(decision_record_build "$ts" "$actor" "$gate" "$verb" "$rat" "$hash")" \
    || { fail "build rejected: $c"; continue; }
  parsed="$(decision_record_parse "$line")" \
    || { fail "parse rejected: $line"; continue; }
  ts2="$(echo "$parsed" | sed -n 's/^ts=//p')"
  ac2="$(echo "$parsed" | sed -n 's/^actor=//p')"
  gt2="$(echo "$parsed" | sed -n 's/^gate=//p')"
  vb2="$(echo "$parsed" | sed -n 's/^verb=//p')"
  rt2="$(echo "$parsed" | sed -n 's/^rationale=//p')"
  ph2="$(echo "$parsed" | sed -n 's/^plan_hash=//p')"
  if [ "$ts" = "$ts2" ] && [ "$actor" = "$ac2" ] && [ "$gate" = "$gt2" ] \
     && [ "$verb" = "$vb2" ] && [ "$rat" = "$rt2" ] && [ "$hash" = "$ph2" ]; then
    pass "round-trip: $c"
  else
    fail "round-trip mismatch: $c → ts=$ts2 actor=$ac2 gate=$gt2 verb=$vb2 rat=$rt2 hash=$ph2"
  fi
done

# --- reject corpus ---
decision_record_build "" user plan approve r h >/dev/null 2>&1
[ $? -eq 2 ] && pass "empty ts rejected" || fail "empty ts accepted"

decision_record_build 2026-05-09T10:00:00Z badactor plan approve r h >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad actor rejected" || fail "bad actor accepted"

decision_record_build 2026-05-09T10:00:00Z user badgate approve r h >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad gate rejected" || fail "bad gate accepted"

decision_record_build 2026-05-09T10:00:00Z user plan badverb r h >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad verb rejected" || fail "bad verb accepted"

decision_record_build 2026-05-09T10:00:00Z user plan approve $'with\nnewline' h >/dev/null 2>&1
[ $? -eq 2 ] && pass "newline in rationale rejected" || fail "newline accepted"

decision_record_build 2026-05-09T10:00:00Z user plan approve $'ansi\x1b[31m' h >/dev/null 2>&1
[ $? -eq 2 ] && pass "ANSI rejected" || fail "ANSI accepted"

# --- determinism (invariant 4) ---
a="$(decision_record_build 2026-05-09T10:00:00Z user plan approve "same input" abc)"
b="$(decision_record_build 2026-05-09T10:00:00Z user plan approve "same input" abc)"
[ "$a" = "$b" ] && pass "determinism" || fail "determinism: $a != $b"

# --- escaping: quotes survive round-trip ---
line="$(decision_record_build 2026-05-09T10:00:00Z user plan approve 'has "quote"' h)"
parsed="$(decision_record_parse "$line")"
echo "$parsed" | grep -q '^rationale=has "quote"$' \
  && pass 'quote escaping round-trip' \
  || fail "quote round-trip: $parsed"

# --- regression: comma + quote + colon combinations (review fix) ---
# The original parser split on top-level ',' and silently truncated any
# rationale containing a comma, returning a half-decoded record. The
# anchored parser MUST round-trip these exactly.
declare -a tricky_rationales=(
  'comma, in rationale'
  'comma,"quote combo'
  'embedded ":" colon'
  'nested {"x":1}'
  'edge \backslash'
  ',leading comma'
  'trailing comma,'
  ',,, multi commas ,,,'
)
for r in "${tricky_rationales[@]}"; do
  line="$(decision_record_build 2026-05-09T10:00:00Z user plan approve "$r" abc)" \
    || { fail "build rejected tricky: $r"; continue; }
  parsed="$(decision_record_parse "$line")" \
    || { fail "parse rejected tricky: $r <- $line"; continue; }
  parsed_r="$(echo "$parsed" | sed -n 's/^rationale=//p')"
  parsed_h="$(echo "$parsed" | sed -n 's/^plan_hash=//p')"
  if [ "$parsed_r" = "$r" ] && [ "$parsed_h" = "abc" ]; then
    pass "tricky round-trip: $r"
  else
    fail "tricky round-trip: in=<$r> out_r=<$parsed_r> out_h=<$parsed_h>"
  fi
done

# --- postcondition: parser MUST fail-closed on malformed records ---
# Missing plan_hash key.
bad='{"ts":"t","actor":"user","gate":"plan","verb":"approve","rationale":"r"}'
decision_record_parse "$bad" >/dev/null 2>&1
[ $? -eq 2 ] && pass "missing key fail-closed" || fail "missing key accepted"

# Trailing junk after the last value.
bad2='{"ts":"t","actor":"user","gate":"plan","verb":"approve","rationale":"r","plan_hash":"h"junk}'
decision_record_parse "$bad2" >/dev/null 2>&1
[ $? -eq 2 ] && pass "trailing junk fail-closed" || fail "trailing junk accepted"

# Unsupported escape sequence (\n is not produced by _dr_jstr).
bad3='{"ts":"t","actor":"user","gate":"plan","verb":"approve","rationale":"a\nb","plan_hash":"h"}'
decision_record_parse "$bad3" >/dev/null 2>&1
[ $? -eq 2 ] && pass "unsupported escape fail-closed" || fail "unsupported escape accepted"

# Keys out of order — the parser anchors on the canonical encoder order.
bad4='{"actor":"user","ts":"t","gate":"plan","verb":"approve","rationale":"r","plan_hash":"h"}'
decision_record_parse "$bad4" >/dev/null 2>&1
[ $? -eq 2 ] && pass "key reorder fail-closed" || fail "key reorder accepted"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures" >&2
  exit 1
fi
echo "OK"
