#!/usr/bin/env bash
# Property + contract tests for scripts/prune-runs.sh.
#
# Properties under test (see docs/specs/run-id-isolation.md "Invariants"):
#   - retention safety: protected (latest/active) is never deleted, even
#     if it is the oldest.
#   - ADR durability: runs containing adrs/*.md are never deleted by retention.
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

# Sandbox. aidp_resolve_artifacts_root unconditionally returns docs/aidp/,
# so we build the sandbox under docs/aidp/. No plugin.json injection needed.
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox" || exit 2
mkdir -p docs/aidp/runs .claude/workflow-state

# Fabricate 15 parseable run-ids with strictly increasing mtimes.
# Use 'touch -t' for portable mtime control.
make_id() { printf '20260508T%06d-a1b2c3-%02x' "$1" "$(( $1 % 256 ))"; }

ids=()
for n in $(seq 1 15); do
  id=$(make_id "$n")
  ids+=("$id")
  mkdir -p "docs/aidp/runs/$id"
  # mtime: 2026-05-08 12:00:0n
  # Portable touch: -t format is [[CC]YY]MMDDhhmm[.SS] = 12 digits + .SS
  ts=$(printf '202605081200.%02d' "$n")
  touch -t "$ts" "docs/aidp/runs/$id"
done

# Newest is ids[14], oldest is ids[0]. Pin "latest" to the OLDEST so we
# can test the protect-against-oldest property.
oldest=${ids[0]}
( cd docs/aidp && ln -sfn "runs/$oldest" "latest.tmp" && mv "latest.tmp" "latest" )
printf '%s\n' "$oldest" > docs/aidp/latest.txt
printf '%s\n' "$oldest" > .claude/workflow-state/active

# Foreign directory must survive.
mkdir -p docs/aidp/runs/not-a-run-id

# ADR-bearing run must survive even if it falls outside retention.
adr_run=${ids[1]}
mkdir -p "docs/aidp/runs/$adr_run/adrs"
printf '%s\n' "# ADR: Keep me" > "docs/aidp/runs/$adr_run/adrs/20260508-keep-me.md"
touch -t 202605081200.02 "docs/aidp/runs/$adr_run"

# Run pruner with RUN_RETENTION=10.
RUN_RETENTION=10 CI=false bash "$PRUNE" >/tmp/prune-out.$$ 2>&1 || {
  cat /tmp/prune-out.$$ >&2
  fail "pruner exited nonzero"
}

remaining=$(find docs/aidp/runs -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
# Expectations: 10 newest + 1 protected (oldest) + 1 ADR + 1 foreign = 13.
if [ "$remaining" -eq 13 ]; then
  pass "kept 13 dirs (10 newest + protected oldest + ADR + foreign)"
else
  fail "expected 13 dirs, got $remaining"
fi

# Protected oldest must still exist.
if [ -d "docs/aidp/runs/$oldest" ]; then
  pass "protected oldest survived"
else
  fail "protected oldest was deleted"
fi

# Foreign survived.
if [ -d "docs/aidp/runs/not-a-run-id" ]; then
  pass "foreign directory survived"
else
  fail "foreign directory was deleted"
fi

# ADR-bearing run survived.
if [ -d "docs/aidp/runs/$adr_run" ]; then
  pass "ADR-bearing run survived"
else
  fail "ADR-bearing run was deleted"
fi

# Newest 10 survived. ids[5..14] (zero-indexed) are the 10 newest.
for i in $(seq 5 14); do
  if [ ! -d "docs/aidp/runs/${ids[$i]}" ]; then
    fail "expected newest survivor missing: ${ids[$i]}"
  fi
done
pass "10 newest by mtime survived"

# Mid-aged unprotected ids[2..4] should be deleted. ids[1] has an ADR.
for i in 2 3 4; do
  if [ -d "docs/aidp/runs/${ids[$i]}" ]; then
    fail "expected deletion missing: ${ids[$i]}"
  fi
done
pass "3 unprotected mid-aged dirs were deleted"

# CI=true: no-op.
mkdir -p docs/aidp/runs/throwaway-not-a-run-id
before=$(find docs/aidp/runs -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
RUN_RETENTION=1 CI=true bash "$PRUNE" >/dev/null 2>&1
after=$(find docs/aidp/runs -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
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
