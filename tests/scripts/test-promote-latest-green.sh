#!/usr/bin/env bash
# Property + contract tests for scripts/promote-latest-green.sh.
#
#   - core: should_promote returns true iff verify=go AND blocking=0 (table).
#   - boundary: bad --verify-status, --review-blocking, --run-id rejected (rc=2).
#   - shell: green path writes all three pointers; non-green is a no-op;
#     dangling target rejected (rc=3); existing latest triplet untouched;
#     idempotent across two consecutive promotes; tmp files cleaned.
#   - prune integration: prune-runs.sh skips a run named in the green pointer.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PROMOTE="${REPO_ROOT}/scripts/promote-latest-green.sh"
PROMOTE_CORE="${REPO_ROOT}/scripts/lib/promote-core.sh"
PRUNE="${REPO_ROOT}/scripts/prune-runs.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PROMOTE" ] || { echo "promote script missing" >&2; exit 2; }
[ -f "$PROMOTE_CORE" ] || { echo "promote core lib missing" >&2; exit 2; }

# A valid run-id used across all sandboxed cases.
GREEN_ID="20260509T120000-a1b2c3-cc"

# --- core: should_promote table ---------------------------------------------
# shellcheck source=scripts/lib/promote-core.sh
source "$PROMOTE_CORE"

check_core() {
  local v="$1" b="$2" expected="$3" label="$4"
  if should_promote "$v" "$b"; then got=true; else got=false; fi
  if [ "$got" = "$expected" ]; then
    pass "core: $label (verify=$v blocking=$b → $got)"
  else
    fail "core: $label expected=$expected got=$got"
  fi
}
check_core "go"    "0" true  "go+0 promotes"
check_core "go"    "1" false "go+1 skips"
check_core "go"    "5" false "go+5 skips"
check_core "no-go" "0" false "no-go+0 skips"
check_core "no-go" "1" false "no-go+1 skips"
check_core "fail"  "0" false "fail+0 skips"
check_core "fail"  "3" false "fail+3 skips"
check_core ""      "0" false "empty verify skips"
check_core "go"    ""  false "empty blocking skips"
# Idempotency: same inputs → same decision twice.
if should_promote "go" "0" && should_promote "go" "0"; then
  pass "core: idempotent on green inputs"
else
  fail "core: not idempotent"
fi

# --- sandbox helper ----------------------------------------------------------
make_sandbox() {
  local sb
  sb=$(mktemp -d)
  mkdir -p "$sb/docs/runs/$GREEN_ID" "$sb/.claude/workflow-state"
  # Existing latest triplet — must be left untouched.
  ( cd "$sb/docs" && ln -sfn "runs/$GREEN_ID" latest )
  printf '%s\n' "$GREEN_ID" > "$sb/docs/latest.txt"
  printf '%s\n' "$GREEN_ID" > "$sb/.claude/workflow-state/active"
  printf '%s' "$sb"
}

snapshot_existing_latest() {
  # Returns "<symlink-target>|<latest.txt>|<active>" of pre-existing pointers.
  local sb="$1"
  printf '%s|%s|%s' \
    "$(readlink "$sb/docs/latest" 2>/dev/null || true)" \
    "$(cat "$sb/docs/latest.txt" 2>/dev/null || true)" \
    "$(cat "$sb/.claude/workflow-state/active" 2>/dev/null || true)"
}

run_promote() {
  # Args: <sandbox> <verify> <blocking> [extra args...]
  local sb="$1" v="$2" b="$3"; shift 3
  ( cd "$sb" && bash "$PROMOTE" \
      --run-id "$GREEN_ID" \
      --verify-status "$v" \
      --review-blocking "$b" \
      "$@" )
}

# --- happy path: green promotes all three pointers ---------------------------
sb=$(make_sandbox)
before=$(snapshot_existing_latest "$sb")
if run_promote "$sb" "go" "0" >/dev/null 2>&1; then
  pass "happy: rc=0 on green"
else
  fail "happy: rc!=0 on green"
fi
if [ -L "$sb/docs/latest-green" ]; then
  t=$(readlink "$sb/docs/latest-green")
  if [ "$t" = "runs/$GREEN_ID" ]; then
    pass "happy: docs/latest-green symlink points at relative runs/<id>"
  else
    fail "happy: bad symlink target: $t"
  fi
else
  fail "happy: docs/latest-green not a symlink"
fi
if [ "$(cat "$sb/docs/latest-green.txt" 2>/dev/null)" = "$GREEN_ID" ]; then
  pass "happy: docs/latest-green.txt content matches"
else
  fail "happy: docs/latest-green.txt content mismatch"
fi
if [ "$(cat "$sb/.claude/workflow-state/active-green" 2>/dev/null)" = "$GREEN_ID" ]; then
  pass "happy: active-green content matches"
else
  fail "happy: active-green content mismatch"
fi
# Existing latest triplet must be byte-identical.
after=$(snapshot_existing_latest "$sb")
if [ "$before" = "$after" ]; then
  pass "happy: existing latest triplet untouched"
else
  fail "happy: latest triplet mutated: $before → $after"
fi
# No tmp residue.
leftover=$(find "$sb/docs" "$sb/.claude/workflow-state" -name '*latest-green.tmp*' -o -name 'active-green.tmp*' 2>/dev/null | head -1)
if [ -z "$leftover" ]; then
  pass "happy: no .tmp residue"
else
  fail "happy: tmp file left behind: $leftover"
fi
# Idempotency: a second invocation produces the same final state.
run_promote "$sb" "go" "0" >/dev/null 2>&1
if [ "$(readlink "$sb/docs/latest-green")" = "runs/$GREEN_ID" ] \
   && [ "$(cat "$sb/docs/latest-green.txt")" = "$GREEN_ID" ] \
   && [ "$(cat "$sb/.claude/workflow-state/active-green")" = "$GREEN_ID" ]; then
  pass "idempotency: second promote matches first"
else
  fail "idempotency: state diverged after second promote"
fi
rm -rf "$sb"

# --- no-op: non-green inputs leave green pointers absent ---------------------
for combo in "no-go 0" "fail 0" "go 1" "go 7"; do
  set -- $combo
  v="$1"; b="$2"
  sb=$(make_sandbox)
  if run_promote "$sb" "$v" "$b" >/dev/null 2>&1; then
    pass "skip: rc=0 on verify=$v blocking=$b"
  else
    fail "skip: non-zero rc on verify=$v blocking=$b"
  fi
  if [ -e "$sb/docs/latest-green" ] || [ -e "$sb/docs/latest-green.txt" ] \
       || [ -e "$sb/.claude/workflow-state/active-green" ]; then
    fail "skip: green pointer leaked on verify=$v blocking=$b"
  else
    pass "skip: no green pointer created on verify=$v blocking=$b"
  fi
  rm -rf "$sb"
done

# --- boundary: bad arguments rejected with rc=2 ------------------------------
sb=$(make_sandbox)
( cd "$sb" && bash "$PROMOTE" --run-id "$GREEN_ID" --verify-status "yes" --review-blocking 0 ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: bad --verify-status → rc=2"; else fail "boundary: bad --verify-status wrong rc"; fi
( cd "$sb" && bash "$PROMOTE" --run-id "$GREEN_ID" --verify-status "go" --review-blocking "-1" ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: negative --review-blocking → rc=2"; else fail "boundary: negative blocking wrong rc"; fi
( cd "$sb" && bash "$PROMOTE" --run-id "$GREEN_ID" --verify-status "go" --review-blocking "abc" ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: non-numeric --review-blocking → rc=2"; else fail "boundary: non-numeric blocking wrong rc"; fi
( cd "$sb" && bash "$PROMOTE" --run-id "../etc/passwd" --verify-status "go" --review-blocking 0 ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: bad --run-id (parser rejects) → rc=2"; else fail "boundary: bad run-id wrong rc"; fi
( cd "$sb" && bash "$PROMOTE" --verify-status "go" --review-blocking 0 ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: missing --run-id → rc=2"; else fail "boundary: missing run-id wrong rc"; fi
( cd "$sb" && bash "$PROMOTE" --run-id "$GREEN_ID" --verify-status "go" --review-blocking 0 --bogus x ) >/dev/null 2>&1
rc=$?; if [ "$rc" = "2" ]; then pass "boundary: unknown flag → rc=2"; else fail "boundary: unknown flag wrong rc"; fi
rm -rf "$sb"

# --- dangling target: docs/runs/<id> missing → rc=3 --------------------------
sb=$(mktemp -d)
mkdir -p "$sb/docs/runs" "$sb/.claude/workflow-state"   # NOTE: no docs/runs/<id>
( cd "$sb" && bash "$PROMOTE" --run-id "$GREEN_ID" --verify-status "go" --review-blocking 0 ) >/dev/null 2>&1
rc=$?
if [ "$rc" = "3" ]; then
  pass "dangling: missing target dir → rc=3"
else
  fail "dangling: expected rc=3 got rc=$rc"
fi
if [ ! -e "$sb/docs/latest-green" ] && [ ! -e "$sb/docs/latest-green.txt" ]; then
  pass "dangling: no green pointer created"
else
  fail "dangling: green pointer created at missing target"
fi
rm -rf "$sb"

# --- atomicity: tmp file never visible at the canonical path -----------------
# We cannot interrupt mv mid-call portably, but we can assert two facts that
# together imply atomicity by construction:
#   (1) After a successful promote, no '*latest-green.tmp.*' files remain.
#   (2) The canonical path is either a symlink to runs/<id> or absent — never
#       a regular file (which is what a half-completed write would look like).
sb=$(make_sandbox)
run_promote "$sb" "go" "0" >/dev/null 2>&1
if [ -L "$sb/docs/latest-green" ] && [ ! -f "$sb/docs/latest-green" ] || [ -L "$sb/docs/latest-green" ]; then
  # -f follows symlinks; the second clause is the meaningful one: it's a symlink.
  pass "atomicity: canonical path is a symlink (never a tmp regular file)"
else
  fail "atomicity: canonical path shape unexpected"
fi
tmp_residue=$(find "$sb/docs" "$sb/.claude/workflow-state" \( -name 'latest-green.tmp.*' -o -name 'latest-green.txt.tmp.*' -o -name 'active-green.tmp.*' \) 2>/dev/null | head -1)
if [ -z "$tmp_residue" ]; then
  pass "atomicity: no tmp residue at canonical path"
else
  fail "atomicity: tmp file visible: $tmp_residue"
fi
rm -rf "$sb"

# --- prune-runs.sh respects the green pointer --------------------------------
sb=$(mktemp -d)
trap 'rm -rf "$sb"' EXIT
cd "$sb" || exit 2
mkdir -p docs/runs .claude/workflow-state
make_id() { printf '20260508T%06d-a1b2c3-%02x' "$1" "$(( $1 % 256 ))"; }
ids=()
for n in $(seq 1 15); do
  id=$(make_id "$n"); ids+=("$id")
  mkdir -p "docs/runs/$id"
  ts=$(printf '202605081200.%02d' "$n")
  touch -t "$ts" "docs/runs/$id"
done
oldest=${ids[0]}
# Pin standard latest pointers to the SECOND oldest so we test green on its own.
second=${ids[1]}
( cd docs && ln -sfn "runs/$second" latest.tmp && mv latest.tmp latest )
printf '%s\n' "$second" > docs/latest.txt
printf '%s\n' "$second" > .claude/workflow-state/active
# Pin GREEN to the OLDEST (would otherwise be deleted at retention=10).
printf '%s\n' "$oldest" > .claude/workflow-state/active-green
( cd docs && ln -sfn "runs/$oldest" latest-green.tmp && mv latest-green.tmp latest-green )
printf '%s\n' "$oldest" > docs/latest-green.txt

RUN_RETENTION=10 CI=false bash "$PRUNE" >/tmp/prune-out.$$ 2>&1 || {
  cat /tmp/prune-out.$$ >&2
  fail "prune: exited nonzero"
}
if [ -d "docs/runs/$oldest" ]; then
  pass "prune: green-pointer target survived retention"
else
  fail "prune: green-pointer target was deleted"
fi
if [ -d "docs/runs/$second" ]; then
  pass "prune: latest target survived retention"
else
  fail "prune: latest target was deleted"
fi
cd / && rm -rf "$sb"
trap - EXIT

if [ "$failures" -gt 0 ]; then
  echo "test-promote-latest-green: FAILED ($failures)" >&2
  exit 1
fi
echo "test-promote-latest-green: OK"
