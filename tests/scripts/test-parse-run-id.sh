#!/usr/bin/env bash
# Contract + property tests for scripts/parse-run-id.sh.
#
# Boundary parser tests per .claude/rules/boundary-parse-dont-validate.md:
#   - accept corpus: every canonical-shaped value parses
#   - reject corpus: every malformed value is rejected
#   - path-traversal counterexamples: '../', '/', '\', '..', NUL, whitespace
#   - property fuzz: 200 random strings — every accepted one round-trips
#     through the regex, and every rejected one fails closed.
#   - containment: an accepted id, when joined onto docs/runs/, resolves
#     to a direct child of docs/runs (no traversal).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-run-id.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

# --- accept corpus ---
accept_cases=(
  "20260508T143022-a1b2c3-7f"      # canonical example with disambiguator
  "20260508T143022Z-a1b2c3"        # with Z, no disambiguator
  "20260508T143022Z-a1b2c3-00"     # with Z and disambiguator
  "20260508T143022-abcdef"         # no Z, no disambiguator
  "00000000T000000-000000"         # boundary numerics
  "99999999T235959Z-ffffff-ff"     # boundary maxes
)
for v in "${accept_cases[@]}"; do
  if bash "$PARSER" "$v" >/dev/null 2>&1; then
    pass "accept: $v"
  else
    fail "accept: $v (parser rejected a valid id)"
  fi
done

# --- reject corpus (path traversal, separators, length, charset) ---
reject_cases=(
  ""                                       # empty
  ".."                                     # traversal token
  "../etc"                                 # traversal sequence
  "20260508T143022-a1b2c3/../etc"          # embedded traversal
  "/20260508T143022-a1b2c3"                # leading slash
  "20260508T143022-a1b2c3/"                # trailing slash
  "20260508T143022-a1b2c3\\foo"            # backslash
  "20260508T143022-A1B2C3"                 # uppercase hex (not allowed)
  "20260508T143022-a1b2c3 "                # trailing whitespace
  " 20260508T143022-a1b2c3"                # leading whitespace
  "20260508T143022-a1b2c3-7"               # disambiguator too short
  "20260508T143022-a1b2c3-7ff"             # disambiguator too long
  "20260508T143022-a1b2cz"                 # non-hex char
  "20260508T143022-a1b2c3-zz"              # non-hex disambiguator
  "20260508-143022-a1b2c3"                 # missing T
  "20260508t143022-a1b2c3"                 # lowercase t (regex requires T)
  "abcdefghT143022-a1b2c3"                 # alpha in date
  "20260508T143022-a1b2c3-7f-extra"        # too long, extra suffix
  "20260508T143022-a1b2c"                  # too short overall (21)
  "20260508T143022Z-a1b2c3-00-extra"       # over-length (29)
)
for v in "${reject_cases[@]}"; do
  if bash "$PARSER" "$v" >/dev/null 2>&1; then
    fail "reject: $(printf '%q' "$v") (parser accepted a malformed id)"
  else
    pass "reject: $(printf '%q' "$v")"
  fi
done

# --- property fuzz: 200 random strings ---
# We don't expect any fuzz string to be accepted; the search space for the
# canonical regex is far too sparse to hit by chance. The property is
# "fail-closed": a parser miss here would surface as an unexpected accept.
fuzz_iters=200
fuzz_accepts=0
for _ in $(seq 1 "$fuzz_iters"); do
  # Random 5..40 byte string from a wide charset (path separators included).
  len=$(( RANDOM % 36 + 5 ))
  cand=$(LC_ALL=C tr -dc 'A-Za-z0-9/.\\ -' </dev/urandom 2>/dev/null | head -c "$len" || true)
  if bash "$PARSER" "$cand" >/dev/null 2>&1; then
    fuzz_accepts=$((fuzz_accepts + 1))
    fail "fuzz unexpectedly accepted: $(printf '%q' "$cand")"
  fi
done
if [ "$fuzz_accepts" -eq 0 ]; then
  pass "fuzz: ${fuzz_iters} random strings, zero unexpected accepts"
fi

# --- containment property ---
# For every accepted id, "docs/runs/<id>" must be a direct child of
# "docs/runs" — no '..' segments, no separators in the basename.
for v in "${accept_cases[@]}"; do
  joined="docs/runs/${v}"
  # The basename of the joined path must equal the original id.
  bn=$(basename "$joined")
  if [ "$bn" != "$v" ]; then
    fail "containment: basename($joined) = $bn, expected $v"
  fi
  # The directory of the joined path must be exactly "docs/runs".
  dn=$(dirname "$joined")
  if [ "$dn" != "docs/runs" ]; then
    fail "containment: dirname($joined) = $dn, expected docs/runs"
  fi
done
pass "containment: every accepted id is a direct child of docs/runs"

# --- sourceability: parse_run_id function and RUN_ID_REGEX exported ---
# shellcheck source=scripts/parse-run-id.sh
source "$PARSER"
if [ -z "${RUN_ID_REGEX:-}" ]; then
  fail "RUN_ID_REGEX not defined after sourcing parser"
else
  pass "sourcing parser exposes RUN_ID_REGEX"
fi
if ! command -v parse_run_id >/dev/null 2>&1; then
  fail "parse_run_id function not defined after sourcing"
else
  pass "sourcing parser exposes parse_run_id function"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-parse-run-id: FAILED ($failures)" >&2
  exit 1
fi
echo "test-parse-run-id: OK"
