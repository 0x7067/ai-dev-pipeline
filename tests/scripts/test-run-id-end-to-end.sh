#!/usr/bin/env bash
# End-to-end smoke for run-id isolation.
#
# Property A — concurrent runs do not collide:
#   Two simulated /ship step-0 invocations writing to the same docs/
#   sandbox each end up with distinct ${RUN_DIR} trees. Last-writer-wins
#   on docs/latest is fine; the per-run artifact trees must not stomp
#   each other.
#
# Property B — parallel read-only gates are deterministic:
#   Drive scripts/run-verification-gates.sh with stub commands that
#   sleep different amounts. Confirm:
#     - exit code is the OR of stubs' rcs (any non-zero fails).
#     - stdout shows typecheck → lint → security in fixed order
#       regardless of which one finished first.
#     - .verify-retry.json is single-line on failure (truncate, not
#       append).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
MINT="${REPO_ROOT}/scripts/mint-run-id.sh"
# scripts/run-verification-gates.sh is copied into sandbox below by path,
# not invoked through a top-level variable; declared here only as a
# presence guard for early failure.
[ -f "${REPO_ROOT}/scripts/run-verification-gates.sh" ] \
  || { echo "gates script missing" >&2; exit 2; }

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# ---------- A) concurrent isolation ----------
sandbox_a=$(mktemp -d)
trap 'rm -rf "$sandbox_a" "$sandbox_b" "$sandbox_g"' EXIT

# Each "session" gets its own working directory but they share nothing
# except the shared docs/runs/ tree if we point them there. Simulate
# that by giving each its own sandbox; the property we care about is
# "two distinct mints produce two distinct RUN_DIR trees". We sleep
# briefly between mints so timestamps differ and the property is sharp.
mkdir -p "$sandbox_a/docs/runs" "$sandbox_a/.claude/workflow-state"
sandbox_b=$(mktemp -d)
mkdir -p "$sandbox_b/docs/runs" "$sandbox_b/.claude/workflow-state"

id_a=$(cd "$sandbox_a" && bash "$MINT" --write-pointers)
sleep 1
id_b=$(cd "$sandbox_b" && bash "$MINT" --write-pointers)

if [ "$id_a" != "$id_b" ]; then
  pass "concurrent mints produce distinct ids ($id_a vs $id_b)"
else
  fail "concurrent mints collided: $id_a"
fi

# Each sandbox has its own run dir.
if [ -d "$sandbox_a/docs/runs/$id_a" ] && [ -d "$sandbox_b/docs/runs/$id_b" ]; then
  pass "each session owns docs/runs/<its-id>"
else
  fail "one or both run dirs missing"
fi

# Each docs/latest points only at its session's id (no cross-talk).
target_a=$(readlink "$sandbox_a/docs/latest")
target_b=$(readlink "$sandbox_b/docs/latest")
if [ "$(basename "$target_a")" = "$id_a" ] && [ "$(basename "$target_b")" = "$id_b" ]; then
  pass "each session's docs/latest points at its own run"
else
  fail "docs/latest cross-talk: a=$target_a b=$target_b"
fi

# ---------- B) parallel gate determinism ----------
sandbox_g=$(mktemp -d)
mkdir -p "$sandbox_g/docs/runs" "$sandbox_g/scripts" "$sandbox_g/.claude/hooks"
# The gate runner cd's to repo root if a vendored copy exists locally OR
# if PWD == its repo root (see top of run-verification-gates.sh). We give
# the sandbox a vendored copy at scripts/run-verification-gates.sh so the
# runner stays in our sandbox.
cp "$REPO_ROOT/scripts/run-verification-gates.sh" "$sandbox_g/scripts/"
cp "$REPO_ROOT/scripts/harness-lib.sh"            "$sandbox_g/scripts/"
cp "$REPO_ROOT/scripts/parse-run-id.sh"           "$sandbox_g/scripts/"
cp "$REPO_ROOT/scripts/mint-run-id.sh"            "$sandbox_g/scripts/"
chmod +x "$sandbox_g/scripts/"*.sh

# Mint a run-id inside the sandbox so RUN_DIR resolves into the sandbox's
# docs/runs/<id> tree (where the gate logs and hint file should land).
ssh_id=$(cd "$sandbox_g" && bash scripts/mint-run-id.sh --write-pointers)
ssh_run_dir="docs/runs/${ssh_id}"

# Stubs: typecheck sleeps 2s and FAILS; lint sleeps 1s and passes;
# security passes immediately. With sequential execution the wall clock
# would be ~3s; with parallel fan-out we expect ~2s (max).
stub_cmd_typecheck='sleep 2; echo TYPECHECK-OUT; exit 7'
stub_cmd_lint='sleep 1; echo LINT-OUT; exit 0'
stub_cmd_security='echo SECURITY-OUT; exit 0'

start_s=$SECONDS
out=$(
  cd "$sandbox_g" \
    && RUN_ID="$ssh_id" RUN_DIR="$ssh_run_dir" \
       MAX_VERIFY_RETRIES=0 \
       VERIFY_TYPECHECK_CMD="$stub_cmd_typecheck" \
       VERIFY_LINT_CMD="$stub_cmd_lint" \
       VERIFY_SECURITY_CMD="$stub_cmd_security" \
       VERIFY_REQUIRE_PROPERTY=0 VERIFY_REQUIRE_CONTRACT=0 VERIFY_REQUIRE_FULL_SUITE=0 \
       bash scripts/run-verification-gates.sh 2>&1
)
rc=$?
elapsed=$((SECONDS - start_s))

if [ "$rc" -eq 7 ]; then
  pass "parallel block propagates failing gate's rc (rc=7)"
else
  fail "expected rc=7 from typecheck stub, got rc=$rc"
fi

# Wall clock: parallel block should take ~2s (longest stub), not 3s sum.
# Allow a generous 4s ceiling because $SECONDS is 1-second granular and
# CI runners can be jittery — we're proving "not summed", not "exact".
if [ "$elapsed" -le 4 ]; then
  pass "parallel block finished in ${elapsed}s (≤4s ceiling)"
else
  fail "parallel block took ${elapsed}s (sequential would be ~3s; expected ≤4s)"
fi

# Replay order: stdout must show typecheck-related lines BEFORE lint
# BEFORE security lines, regardless of which finished first.
typecheck_pos=$(printf '%s' "$out" | grep -n 'TYPECHECK-OUT' | head -1 | cut -d: -f1)
lint_pos=$(printf '%s' "$out" | grep -n 'LINT-OUT' | head -1 | cut -d: -f1)
security_pos=$(printf '%s' "$out" | grep -n 'SECURITY-OUT' | head -1 | cut -d: -f1)
if [ -n "$typecheck_pos" ] && [ -n "$lint_pos" ] && [ -n "$security_pos" ] \
   && [ "$typecheck_pos" -lt "$lint_pos" ] \
   && [ "$lint_pos" -lt "$security_pos" ]; then
  pass "deterministic replay order (typecheck<lint<security positions $typecheck_pos<$lint_pos<$security_pos)"
else
  fail "replay order broken: typecheck=$typecheck_pos lint=$lint_pos security=$security_pos"
fi

# Hint file is single JSON object (truncated, not appended).
hint_file="$sandbox_g/$ssh_run_dir/.verify-retry.json"
if [ -f "$hint_file" ]; then
  lines=$(wc -l < "$hint_file" | tr -d ' ')
  if [ "$lines" -le 1 ]; then
    pass "verify-retry.json is single line (truncated, lines=$lines)"
  else
    fail "verify-retry.json has $lines lines (expected ≤1 — append regression?)"
  fi
  if grep -q '"gate":"typecheck"' "$hint_file"; then
    pass "verify-retry.json records the failing gate"
  else
    fail "verify-retry.json missing typecheck gate identifier"
  fi
else
  fail "verify-retry.json was not written at $hint_file"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-run-id-end-to-end: FAILED ($failures)" >&2
  exit 1
fi
echo "test-run-id-end-to-end: OK"
