#!/usr/bin/env bash
# Property test: write-manifest.sh output is accepted by parse-manifest.sh,
# and core builders are deterministic (byte-identical for identical inputs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
WRITER="${REPO_ROOT}/scripts/write-manifest.sh"
PARSER="${REPO_ROOT}/scripts/parse-manifest.sh"
CORE="${REPO_ROOT}/scripts/lib/manifest-core.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$WRITER" ] || { echo "writer missing at $WRITER" >&2; exit 2; }
[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }
[ -f "$CORE" ]   || { echo "core missing at $CORE" >&2; exit 2; }

# --- Determinism check on core builders. ---
# shellcheck source=scripts/lib/manifest-core.sh
source "$CORE"

a=$(manifest_build_entry "plan" "current-plan.md" "0000000000000000000000000000000000000000000000000000000000000000" 12)
b=$(manifest_build_entry "plan" "current-plan.md" "0000000000000000000000000000000000000000000000000000000000000000" 12)
if [ "$a" = "$b" ]; then
  pass "manifest_build_entry deterministic"
else
  fail "manifest_build_entry not deterministic"
fi

arr=$(manifest_build_entries_array "$a")
m1=$(manifest_build "20260508T143022-a1b2c3" "2026-05-08T14:30:22Z" "2026-05-08T14:30:25Z" "ship" "auto" "low" "ok" "deadbeef" "main" "false" "$arr")
m2=$(manifest_build "20260508T143022-a1b2c3" "2026-05-08T14:30:22Z" "2026-05-08T14:30:25Z" "ship" "auto" "low" "ok" "deadbeef" "main" "false" "$arr")
if [ "$m1" = "$m2" ]; then
  pass "manifest_build deterministic"
else
  fail "manifest_build not deterministic"
fi

# --- Round-trip: writer output parses back successfully. ---
tmpdir=$(mktemp -d -t manifest-rt.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

RUN_ID="20260508T143022-a1b2c3-7f"
RUN_DIR="$tmpdir/runs/$RUN_ID"
mkdir -p "$RUN_DIR/research" "$RUN_DIR/adrs"
echo "plan body" > "$RUN_DIR/current-plan.md"
echo "research note" > "$RUN_DIR/research/topic.md"
echo "# ADR: Test" > "$RUN_DIR/adrs/20260508-test.md"

if RUN_ID="$RUN_ID" RUN_DIR="$RUN_DIR" bash "$WRITER" --command ship --mode auto --risk-tier low --status ok > "$tmpdir/writer.out" 2> "$tmpdir/writer.err"; then
  pass "writer succeeded"
else
  echo "writer stderr:" >&2; cat "$tmpdir/writer.err" >&2
  fail "writer failed"
fi

if [ -f "$RUN_DIR/manifest.json" ]; then
  pass "manifest.json exists at expected path"
else
  fail "manifest.json missing"
fi
if grep -q '"kind":"adr","path":"adrs/20260508-test.md"' "$RUN_DIR/manifest.json"; then
  pass "writer classifies ADR artifacts"
else
  fail "writer did not classify ADR artifact kind"
fi

# Parse what the writer produced — assert parse(write(M)) == M.
# Build the source-of-truth set: sorted relpaths under RUN_DIR (excluding
# manifest.json and symlinks) plus the run_id/command/status we passed in.
expected_paths=$(LC_ALL=C find "$RUN_DIR" -type f \
  \! -name manifest.json -print | sed -E "s#^$RUN_DIR/##" | LC_ALL=C sort)
expected_count=$(printf '%s\n' "$expected_paths" | sed '/^$/d' | wc -l | tr -d ' ')

if out=$(bash "$PARSER" "$RUN_DIR/manifest.json" 2>"$tmpdir/parse.err"); then
  parsed_run_id=$(grep '^run_id=' <<<"$out" | head -1 | cut -d= -f2-)
  parsed_command=$(grep '^command=' <<<"$out" | head -1 | cut -d= -f2-)
  parsed_status=$(grep '^status=' <<<"$out" | head -1 | cut -d= -f2-)
  parsed_count=$(grep '^artifact_count=' <<<"$out" | head -1 | cut -d= -f2-)
  parsed_paths=$(grep '^artifact=' <<<"$out" | sed 's/^artifact=//' | LC_ALL=C sort)

  if [ "$parsed_run_id" = "$RUN_ID" ]; then
    pass "round-trip: run_id equality"
  else
    fail "round-trip: run_id mismatch: parsed='$parsed_run_id' expected='$RUN_ID'"
  fi
  if [ "$parsed_command" = "ship" ]; then
    pass "round-trip: command equality"
  else
    fail "round-trip: command mismatch: '$parsed_command'"
  fi
  if [ "$parsed_status" = "ok" ]; then
    pass "round-trip: status equality"
  else
    fail "round-trip: status mismatch: '$parsed_status'"
  fi
  if [ "$parsed_count" = "$expected_count" ]; then
    pass "round-trip: artifact_count equality ($expected_count)"
  else
    fail "round-trip: artifact_count: parsed=$parsed_count expected=$expected_count"
  fi
  if [ "$parsed_paths" = "$expected_paths" ]; then
    pass "round-trip: relpath set equality"
  else
    fail "round-trip: path set mismatch:
parsed:
$parsed_paths
expected:
$expected_paths"
  fi
else
  echo "parse stderr:" >&2; cat "$tmpdir/parse.err" >&2
  fail "round-trip: parser rejected writer output"
fi

# --- BLOCKING-2 regression: TAB / NL / CR in filenames are refused. ---
for ch_label in TAB NL CR; do
  case "$ch_label" in
    TAB) bad_name=$'with\ttab.md' ;;
    NL)  bad_name=$'with\nnl.md' ;;
    CR)  bad_name=$'with\rcr.md' ;;
  esac
  RID="20260508T143022-a1b2c3-bb"
  RD="$tmpdir/refuse-$ch_label/$RID"
  mkdir -p "$RD"
  # printf cannot expand the literal NL inside the > target via shell IO;
  # use explicit redirection (bash handles the byte fine in arg).
  : > "$RD/$bad_name"
  printf 'hi' > "$RD/$bad_name"
  if RUN_ID="$RID" RUN_DIR="$RD" bash "$WRITER" --command ship --status ok \
      >"$tmpdir/refuse-$ch_label.out" 2>"$tmpdir/refuse-$ch_label.err"; then
    fail "writer accepted $ch_label-in-filename (should refuse)"
  else
    if grep -q "TAB/NL/CR" "$tmpdir/refuse-$ch_label.err"; then
      pass "writer refused $ch_label in filename with explicit error"
    else
      fail "writer rejected $ch_label but wrong error message: $(cat "$tmpdir/refuse-$ch_label.err")"
    fi
  fi
done

# --- Property: 25 random small filenames; writer + parser still agree. ---
fuzz_pass=0
fuzz_total=25
for i in $(seq 1 $fuzz_total); do
  RID="20260508T143022-a1b2c3-$(printf '%02x' "$((i%256))")"
  RD="$tmpdir/fuzz/$RID"
  mkdir -p "$RD"
  # Charset includes space (round-trippable) plus alnum, hyphen, dot, underscore.
  # TAB/NL/CR are exercised separately above as REJECT cases.
  fname=$(LC_ALL=C tr -dc 'a-zA-Z0-9 ._-' </dev/urandom 2>/dev/null | head -c 12)
  [ -z "$fname" ] && fname="file$i"
  echo "data $i" > "$RD/${fname}.md"
  expected_path="${fname}.md"
  if RUN_ID="$RID" RUN_DIR="$RD" bash "$WRITER" >/dev/null 2>&1; then
    if pout=$(bash "$PARSER" "$RD/manifest.json" 2>/dev/null); then
      # Parse(write(M))==M: parsed run_id and the relpath both equal source.
      pr=$(grep '^run_id=' <<<"$pout" | head -1 | cut -d= -f2-)
      pp=$(grep '^artifact=' <<<"$pout" | head -1 | sed 's/^artifact=//')
      if [ "$pr" = "$RID" ] && [ "$pp" = "$expected_path" ]; then
        fuzz_pass=$((fuzz_pass+1))
      fi
    fi
  fi
done
if [ "$fuzz_pass" -eq "$fuzz_total" ]; then
  pass "fuzz round-trip: $fuzz_pass/$fuzz_total"
else
  fail "fuzz round-trip: only $fuzz_pass/$fuzz_total passed"
fi

if [ "$failures" -gt 0 ]; then
  echo "roundtrip_test: FAILED ($failures)" >&2
  exit 1
fi
echo "roundtrip_test: OK"
