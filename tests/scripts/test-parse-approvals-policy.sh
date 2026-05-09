#!/usr/bin/env bash
# Contract tests for scripts/parse-approvals-policy.sh.
#
# Per .claude/rules/boundary-parse-dont-validate.md, exercise both accept
# and reject corpora; per security-baseline.md, the parser MUST fail
# closed on every malformed input.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-approvals-policy.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Real policy parses.
out="$(bash "$PARSER" "${REPO_ROOT}/.claude/policy/approvals.yaml" 2>&1)" \
  && pass "real policy accepts" \
  || fail "real policy rejected: $out"

# Required keys present.
echo "$out" | grep -q '^version=1$' && pass "version=1 emitted" || fail "version missing"
echo "$out" | grep -q '^plan_gate_verbs\[1\]=edit$' && pass "edit in plan verbs" || fail "edit missing"
! echo "$out" | grep -q '^release_gate.verbs\[.*\]=edit$' \
  && pass "edit absent from release verbs" \
  || fail "edit leaked into release verbs"

# Reject: missing file.
bash "$PARSER" "${tmpdir}/nope.yaml" >/dev/null 2>&1
[ $? -eq 2 ] && pass "missing file → exit 2" || fail "missing file accepted"

# Reject: bad version.
cat >"${tmpdir}/badver.yaml" <<EOF
version: 2
modes:
  - auto
  - strict
EOF
bash "$PARSER" "${tmpdir}/badver.yaml" >/dev/null 2>&1
[ $? -eq 2 ] && pass "bad version → exit 2" || fail "bad version accepted"

# Reject: edit in release verbs (invariant 8).
cat >"${tmpdir}/editrelease.yaml" <<EOF
version: 1
modes:
  - auto
  - strict
release_gate:
  verbs:
    - approve
    - edit
    - reject
EOF
bash "$PARSER" "${tmpdir}/editrelease.yaml" >/dev/null 2>&1
[ $? -eq 2 ] && pass "edit in release_gate.verbs → exit 2" || fail "edit-in-release accepted"

# Reject: missing modes.
cat >"${tmpdir}/nomodes.yaml" <<EOF
version: 1
plan_gate:
  auto:
    low: skip
EOF
bash "$PARSER" "${tmpdir}/nomodes.yaml" >/dev/null 2>&1
[ $? -eq 2 ] && pass "missing modes → exit 2" || fail "missing modes accepted"

# Reject: tab indent.
printf 'version: 1\nmodes:\n\t- auto\n' >"${tmpdir}/tabs.yaml"
bash "$PARSER" "${tmpdir}/tabs.yaml" >/dev/null 2>&1
[ $? -eq 2 ] && pass "tab indent → exit 2" || fail "tab indent accepted"

if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures" >&2
  exit 1
fi
echo "OK"
