#!/usr/bin/env bash
# Property + contract tests for scripts/prune-runs.sh.
#
# Properties under test (see docs/specs/run-id-isolation.md "Invariants"):
#   - retention safety: protected (latest/active) is never deleted, even
#     if it is the oldest.
#   - count: with N synthetic runs and RUN_RETENTION=K, the pruner keeps
#     min(N, K) directories (plus any protected stragglers).
#   - foreign tolerance: a directory whose name doesn't parse is never
#     deleted by the pruner.
#   - CI no-op: with CI=true, the pruner returns 0 without removing
#     anything.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PRUNE="${REPO_ROOT}/scripts/prune-runs.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Sandbox.
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox" || exit 2
mkdir -p docs/runs .claude/workflow-state

# Fabricate 15 parseable run-ids with strictly increasing mtimes.
# Use 'touch -t' for portable mtime control.
make_id() { printf '20260508T%06d-a1b2c3-%02x' "$1" "$(( $1 % 256 ))"; }

ids=()
for n in $(seq 1 15); do
  id=$(make_id "$n")
  ids+=("$id")
  mkdir -p "docs/runs/$id"
  # mtime: 2026-05-08 12:00:0n
  # Portable touch: -t format is [[CC]YY]MMDDhhmm[.SS] = 12 digits + .SS
  ts=$(printf '202605081200.%02d' "$n")
  touch -t "$ts" "docs/runs/$id"
done

# Newest is ids[14], oldest is ids[0]. Pin "latest" to the OLDEST so we
# can test the protect-against-oldest property.
oldest=${ids[0]}
( cd docs && ln -sfn "runs/$oldest" "latest.tmp" && mv "latest.tmp" "latest" )
printf '%s\n' "$oldest" > docs/latest.txt
printf '%s\n' "$oldest" > .claude/workflow-state/active

# Foreign directory must survive.
mkdir -p docs/runs/not-a-run-id

# Run pruner with RUN_RETENTION=10.
RUN_RETENTION=10 CI=false bash "$PRUNE" >/tmp/prune-out.$$ 2>&1 || {
  cat /tmp/prune-out.$$ >&2
  fail "pruner exited nonzero"
}

remaining=$(find docs/runs -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
# Expectations: 10 newest + 1 protected (oldest) + 1 foreign = 12.
if [ "$remaining" -eq 12 ]; then
  pass "kept 12 dirs (10 newest + protected oldest + foreign)"
else
  fail "expected 12 dirs, got $remaining"
fi

# Protected oldest must still exist.
if [ -d "docs/runs/$oldest" ]; then
  pass "protected oldest survived"
else
  fail "protected oldest was deleted"
fi

# Foreign survived.
if [ -d "docs/runs/not-a-run-id" ]; then
  pass "foreign directory survived"
else
  fail "foreign directory was deleted"
fi

# Newest 10 survived. ids[5..14] (zero-indexed) are the 10 newest.
for i in $(seq 5 14); do
  if [ ! -d "docs/runs/${ids[$i]}" ]; then
    fail "expected newest survivor missing: ${ids[$i]}"
  fi
done
pass "10 newest by mtime survived"

# Mid-aged unprotected ids[1..4] should be deleted.
for i in 1 2 3 4; do
  if [ -d "docs/runs/${ids[$i]}" ]; then
    fail "expected deletion missing: ${ids[$i]}"
  fi
done
pass "4 unprotected mid-aged dirs were deleted"

# CI=true: no-op.
mkdir -p docs/runs/throwaway-not-a-run-id
before=$(find docs/runs -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
RUN_RETENTION=1 CI=true bash "$PRUNE" >/dev/null 2>&1
after=$(find docs/runs -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
if [ "$before" = "$after" ]; then
  pass "CI=true: no-op (count $before unchanged)"
else
  fail "CI=true: deletions occurred ($before → $after)"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-prune-runs: FAILED ($failures)" >&2
  exit 1
fi
echo "test-prune-runs: OK"
