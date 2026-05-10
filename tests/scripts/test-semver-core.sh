#!/usr/bin/env bash
# Property + contract tests for scripts/release/lib/semver-core.sh.
#
# Properties asserted:
#   - I3 round-trip: format_semver(parse_semver(s)) == s on the accept set.
#   - I2 monotonicity: next_version(v, b) > v under SemVer ordering for
#     every (v, b ∈ {patch,minor,major}) in the accept set.
#   - Reject set: malformed inputs return non-zero with no stdout.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/release/lib/semver-core.sh
source "$REPO_ROOT/scripts/release/lib/semver-core.sh"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

ACCEPT=(
  "0.0.0"
  "0.1.0"
  "0.15.1"
  "1.0.0"
  "1.2.3"
  "10.20.30"
  "999.0.1"
)

REJECT=(
  ""
  "v1.2.3"
  "1.2"
  "1.2.3.4"
  "1.2.3-rc.1"
  "1.2.3+build"
  "01.2.3"
  "1.02.3"
  "1.2.03"
  "a.b.c"
  "1.-1.0"
)

# Round-trip + monotonicity
for v in "${ACCEPT[@]}"; do
  parts="$(parse_semver "$v")" || { fail "parse rejected accept: $v"; continue; }
  read -r M m p <<<"$parts"
  rt="$(format_semver "$M" "$m" "$p")"
  if [[ "$rt" == "$v" ]]; then
    pass "round-trip: $v"
  else
    fail "round-trip mismatch: $v -> $rt"
  fi

  for bump in patch minor major; do
    nxt="$(next_version "$v" "$bump")" || { fail "next_version failed: $v $bump"; continue; }
    cmp="$(compare_semver "$nxt" "$v")"
    if [[ "$cmp" == "1" ]]; then
      pass "monotonic: $v --$bump--> $nxt"
    else
      fail "non-monotonic: $v --$bump--> $nxt (cmp=$cmp)"
    fi
  done
done

# Reject set
for s in "${REJECT[@]}"; do
  if out="$(parse_semver "$s" 2>/dev/null)"; then
    fail "parse accepted reject input '$s' -> '$out'"
  else
    pass "reject: '$s'"
  fi
done

# Specific bump arithmetic
got="$(next_version "0.15.1" "patch")"; [[ "$got" == "0.15.2" ]] && pass "0.15.1 patch -> 0.15.2" || fail "patch arithmetic: got $got"
got="$(next_version "0.15.1" "minor")"; [[ "$got" == "0.16.0" ]] && pass "0.15.1 minor -> 0.16.0" || fail "minor arithmetic: got $got"
got="$(next_version "0.15.1" "major")"; [[ "$got" == "1.0.0"  ]] && pass "0.15.1 major -> 1.0.0"  || fail "major arithmetic: got $got"
got="$(next_version "1.2.3"  "minor")"; [[ "$got" == "1.3.0"  ]] && pass "1.2.3 minor zeros patch" || fail "minor zero-out: got $got"
got="$(next_version "1.2.3"  "major")"; [[ "$got" == "2.0.0"  ]] && pass "1.2.3 major zeros minor+patch" || fail "major zero-out: got $got"

# Bad bump kind rejected
if next_version "1.2.3" "bogus" >/dev/null 2>&1; then
  fail "next_version accepted unknown bump kind"
else
  pass "next_version rejects unknown bump kind"
fi

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
