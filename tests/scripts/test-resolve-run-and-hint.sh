#!/usr/bin/env bash
# Contract + property tests for two invariants under-covered by the
# initial run-id test suite:
#
#   - Invariant 1 (parse-once / fail-closed): scripts/resolve-run.sh
#     never echoes an unparsed run-id from any of its four sources. A
#     present-but-malformed source exits 2 rather than fall through.
#
#   - Invariant 5 (verify-retry hint isolation, truncation): repeated
#     write_retry_hint calls — including from concurrent sibling gates —
#     leave the hint file containing exactly one complete JSON object
#     (no append regressions, no interleaved bytes).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
RESOLVE="${REPO_ROOT}/scripts/resolve-run.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$RESOLVE" ] || { echo "resolve script missing" >&2; exit 2; }
[ -f "${REPO_ROOT}/scripts/run-verification-gates.sh" ] \
  || { echo "gates script missing" >&2; exit 2; }

VALID_ID="20260508T143022-a1b2c3-7f"
POISON_TRAVERSAL="../../../../etc/passwd"
POISON_SLASH="foo/bar"
POISON_EMPTY_GARBAGE="not a valid id"

# Each case uses its own sandbox + cwd so resolve-run.sh's anchored probes
# are isolated from the live repo. We drop a plugin.json with the
# ai-dev-pipeline name into each sandbox so aidp_resolve_artifacts_root
# classifies it as plugin-self and uses the legacy <root>/docs layout the
# original tests were written against — the resolve-run contract is what
# this file exercises, not the consumer-vs-plugin classifier (which has
# its own test in scripts/tests/test-project-root.sh).
make_sandbox() {
  local sb
  sb=$(mktemp -d)
  mkdir -p "$sb/.claude/workflow-state" "$sb/docs/aidp" "$sb/.claude-plugin"
  printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' \
    > "$sb/.claude-plugin/plugin.json"
  printf '%s\n' "$sb"
}

# ============================================================================
# A. resolve-run.sh — fail-closed contract
# ============================================================================

# A1: env $RUN_ID accepts a valid id and echoes it verbatim.
sb=$(make_sandbox)
got=$( cd "$sb" && RUN_ID="$VALID_ID" bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "$VALID_ID" ]; then
  pass "env RUN_ID with valid id → echoed (rc=0)"
else
  fail "valid env id rejected (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A2: env $RUN_ID with traversal poison → exit 2, no echo.
sb=$(make_sandbox)
got=$( cd "$sb" && RUN_ID="$POISON_TRAVERSAL" bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then
  pass "env RUN_ID with '../' traversal → exit 2, nothing echoed"
else
  fail "traversal poison was not rejected fail-closed (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A3: env $RUN_ID with embedded slash → exit 2, no echo.
sb=$(make_sandbox)
got=$( cd "$sb" && RUN_ID="$POISON_SLASH" bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then
  pass "env RUN_ID with embedded slash → exit 2, nothing echoed"
else
  fail "slash poison was not rejected fail-closed (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A4: workflow-state/active malformed → exit 2 (no fall-through to docs/aidp/latest).
# A clean docs/aidp/latest.txt is present; if the resolver fell through we'd
# get $VALID_ID2. Fail-closed semantics require exit 2 instead.
VALID_ID2="20260509T091500Z-deadbe-01"
sb=$(make_sandbox)
printf '%s\n' "$POISON_EMPTY_GARBAGE" > "$sb/.claude/workflow-state/active"
printf '%s\n' "$VALID_ID2" > "$sb/docs/aidp/latest.txt"
got=$( cd "$sb" && unset RUN_ID && bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then
  pass "malformed active pointer → exit 2 (no fall-through to docs/aidp/latest)"
else
  fail "fall-through to clean docs/aidp/latest happened despite poisoned active (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A5: docs/aidp/latest.txt malformed → exit 2.
sb=$(make_sandbox)
printf '%s\n' "$POISON_TRAVERSAL" > "$sb/docs/aidp/latest.txt"
got=$( cd "$sb" && unset RUN_ID && bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$got" ]; then
  pass "malformed docs/aidp/latest.txt → exit 2, nothing echoed"
else
  fail "docs/aidp/latest.txt poison echoed (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A6: nothing set → exit 1 (no active run; distinct from poison case).
sb=$(make_sandbox)
got=$( cd "$sb" && unset RUN_ID && bash "$RESOLVE" id 2>/dev/null )
rc=$?
if [ "$rc" -eq 1 ] && [ -z "$got" ]; then
  pass "no source set → exit 1 (no active run)"
else
  fail "expected rc=1 with nothing set (rc=$rc got=$got)"
fi
rm -rf "$sb"

# A7: 'dir' subcommand returns <artifacts-root>/runs/<id> for a valid
# env id. Under the plugin-self sandbox (see make_sandbox), artifacts
# root resolves to <sb>/docs, canonicalized via pwd -P.
sb=$(make_sandbox)
sb_canonical=$( cd "$sb" >/dev/null 2>&1 && pwd -P )
got=$( cd "$sb" && RUN_ID="$VALID_ID" bash "$RESOLVE" dir 2>/dev/null )
rc=$?
if [ "$rc" -eq 0 ] && [ "$got" = "${sb_canonical}/docs/aidp/runs/${VALID_ID}" ]; then
  pass "'dir' subcommand returns <artifacts-root>/runs/<id>"
else
  fail "'dir' subcommand wrong (rc=$rc got=$got want=${sb_canonical}/docs/aidp/runs/${VALID_ID})"
fi
rm -rf "$sb"

# ============================================================================
# B. Verify-retry hint truncation under repeated + concurrent writes
# ============================================================================
#
# We invoke run-verification-gates.sh in a sandbox with stub gates that
# all fail. The end-to-end smoke test (test-run-id-end-to-end.sh) already
# covers the "single failure leaves a single-object file" case. Here we
# stress two new properties:
#
#   B1: When all three parallel gates fail, the hint file contains
#       exactly one well-formed JSON object — no concatenation, no
#       interleaved bytes from concurrent writers.
#
#   B2: Running the gate runner a SECOND time on the same hint path
#       (a retry envelope) leaves a single object reflecting the
#       latest run, never a multi-object append.

sb_g=$(mktemp -d)
trap 'rm -rf "$sb_g"' EXIT
mkdir -p "$sb_g/scripts/lib" "$sb_g/.claude/hooks" "$sb_g/.claude-plugin"
# Plugin-self manifest keeps the sandbox on the legacy docs/ layout (see
# make_sandbox above); without it mint-run-id would write under docs/aidp/.
printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' \
  > "$sb_g/.claude-plugin/plugin.json"
cp "$REPO_ROOT/scripts/run-verification-gates.sh" "$sb_g/scripts/"
cp "$REPO_ROOT/scripts/harness-lib.sh"            "$sb_g/scripts/"
cp "$REPO_ROOT/scripts/parse-run-id.sh"           "$sb_g/scripts/"
cp "$REPO_ROOT/scripts/mint-run-id.sh"            "$sb_g/scripts/"
cp "$REPO_ROOT/scripts/lib/style.sh"              "$sb_g/scripts/lib/"
cp "$REPO_ROOT/scripts/lib/project-root.sh"       "$sb_g/scripts/lib/"
chmod +x "$sb_g/scripts/"*.sh

run_id=$( cd "$sb_g" && bash scripts/mint-run-id.sh --write-pointers )
run_dir="docs/aidp/runs/${run_id}"
hint_path="${sb_g}/${run_dir}/.verify-retry.json"

# B1: three concurrent failures. Output captured but not asserted on
# (we assert on the hint file); discard to keep shellcheck happy.
_out=$(
  cd "$sb_g" \
    && RUN_ID="$run_id" RUN_DIR="$run_dir" \
       VERIFY_TYPECHECK_CMD='sleep 1; echo TC; exit 11' \
       VERIFY_LINT_CMD='sleep 1; echo LI; exit 13' \
       VERIFY_SECURITY_CMD='sleep 1; echo SE; exit 17' \
       VERIFY_REQUIRE_PROPERTY=0 VERIFY_REQUIRE_CONTRACT=0 VERIFY_REQUIRE_FULL_SUITE=0 \
       bash scripts/run-verification-gates.sh 2>&1
) || true

if [ -f "$hint_path" ]; then
  lines=$(wc -l < "$hint_path" | tr -d ' ')
  bytes=$(wc -c < "$hint_path" | tr -d ' ')
  # Exactly one trailing newline → wc -l reports 1.
  if [ "$lines" -eq 1 ]; then
    pass "concurrent triple-failure: hint file is single line (lines=$lines, bytes=$bytes)"
  else
    fail "concurrent triple-failure: hint file has $lines lines (append/interleave regression)"
  fi
  # Exactly one JSON object: starts with {, ends with } before the newline,
  # and contains no '}{' boundary that would prove concatenation.
  content=$(cat "$hint_path")
  case "$content" in
    *'}{'*) fail "hint file contains '}{' boundary — concatenated writes detected" ;;
    \{*\})  pass "hint file contains exactly one well-formed JSON object" ;;
    *)      fail "hint file is not a single JSON object: $content" ;;
  esac
  # Last writer wins: gate field must be one of the three labels.
  case "$content" in
    *'"gate":"typecheck"'*|*'"gate":"lint"'*|*'"gate":"security"'*)
      pass "hint file records exactly one of the three failing gates" ;;
    *)
      fail "hint file gate field unexpected: $content" ;;
  esac
else
  fail "hint file not written under triple-failure"
fi

# B2: re-run with a single failure; previous content must be replaced,
# not appended to. (Output discarded; assertion is on the hint file.)
_out2=$(
  cd "$sb_g" \
    && RUN_ID="$run_id" RUN_DIR="$run_dir" \
       VERIFY_TYPECHECK_CMD='echo TC2; exit 0' \
       VERIFY_LINT_CMD='echo LI2; exit 0' \
       VERIFY_SECURITY_CMD='echo SE2; exit 23' \
       VERIFY_REQUIRE_PROPERTY=0 VERIFY_REQUIRE_CONTRACT=0 VERIFY_REQUIRE_FULL_SUITE=0 \
       bash scripts/run-verification-gates.sh 2>&1
) || true

if [ -f "$hint_path" ]; then
  lines=$(wc -l < "$hint_path" | tr -d ' ')
  content=$(cat "$hint_path")
  if [ "$lines" -eq 1 ]; then
    pass "re-run on same hint path: still single line (truncate, not append)"
  else
    fail "re-run on same hint path: $lines lines (append regression)"
  fi
  case "$content" in
    *'"gate":"security"'*'"exit_code":23'*)
      pass "re-run hint reflects latest failing gate (security/rc=23)" ;;
    *)
      fail "re-run hint did not reflect latest failure: $content" ;;
  esac
else
  fail "hint file missing after re-run"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-resolve-run-and-hint: FAILED ($failures)" >&2
  exit 1
fi
echo "test-resolve-run-and-hint: OK"
