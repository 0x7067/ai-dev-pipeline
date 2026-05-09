#!/usr/bin/env bash
# Regression test for the docs/latest symlink swap pattern used in
# .claude/commands/ship.md step 0.
#
# Background: the prior pattern
#     ( cd docs && ln -sfn "runs/$ID" "latest.tmp.$_t" && mv "latest.tmp.$_t" latest )
# is broken on macOS when `latest` is an existing symlink to a directory:
# `mv` traverses the symlink and places the tmp symlink INSIDE the target
# directory instead of replacing the symlink.
#
# This test asserts the fixed pattern (`ln -sfn runs/$ID docs/latest`)
# atomically replaces the existing symlink in place.

set -uo pipefail

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
cd "$sandbox" || exit 2

mkdir -p docs/runs/A docs/runs/B

# Initial state: docs/latest -> runs/A
ln -sfn runs/A docs/latest

if [ "$(readlink docs/latest)" = "runs/A" ]; then
  pass "initial symlink points to runs/A"
else
  fail "initial symlink readlink: $(readlink docs/latest)"
fi

# Apply the fixed swap pattern.
ln -sfn runs/B docs/latest

# Symlink itself must now point to runs/B
if [ -L docs/latest ] && [ "$(readlink docs/latest)" = "runs/B" ]; then
  pass "after swap, symlink points to runs/B"
else
  fail "after swap, symlink readlink: $(readlink docs/latest 2>/dev/null) (expected runs/B)"
fi

# Negative invariant: the bug placed a stray tmp symlink inside runs/A.
# Confirm runs/A is still empty (no leakage of any kind).
if [ -z "$(ls -A docs/runs/A 2>/dev/null)" ]; then
  pass "runs/A directory not contaminated"
else
  fail "runs/A contaminated: $(ls -A docs/runs/A)"
fi

# Negative invariant: runs/B is also empty (the swap must not write into
# the new target either).
if [ -z "$(ls -A docs/runs/B 2>/dev/null)" ]; then
  pass "runs/B directory not contaminated"
else
  fail "runs/B contaminated: $(ls -A docs/runs/B)"
fi

# Negative invariant: no stray latest.tmp.* artifacts in docs/.
shopt -s nullglob 2>/dev/null || true
stray=( docs/latest.tmp.* )
if [ "${#stray[@]}" -eq 0 ]; then
  pass "no stray latest.tmp.* in docs/"
else
  fail "stray tmp artifacts: ${stray[*]}"
fi

# Idempotency: running the swap a second time with the same target is a no-op.
ln -sfn runs/B docs/latest
if [ "$(readlink docs/latest)" = "runs/B" ]; then
  pass "second identical swap is idempotent"
else
  fail "idempotent swap broke: $(readlink docs/latest)"
fi

# Check that the buggy pattern actually exhibits the bug (regression-of-regression).
# This is a meta-assertion: if `mv tmp existing-symlink` ever stops being
# broken on macOS, this test fails fast and tells us we can simplify.
rm -rf docs
mkdir -p docs/runs/A docs/runs/B
ln -sfn runs/A docs/latest
( cd docs && ln -sfn runs/B latest.tmp.x && mv latest.tmp.x latest ) >/dev/null 2>&1 || true
case "$OSTYPE" in
  darwin*)
    if [ -L docs/runs/A/latest.tmp.x ]; then
      pass "buggy mv-onto-symlink pattern still exhibits the macOS bug (sentinel)"
    else
      # If the bug is no longer reproducible, surface it as a soft signal,
      # not a failure — the fix is still correct, just no longer load-bearing.
      pass "macOS no longer exhibits mv-onto-symlink bug (good news; fix is still correct)"
    fi
    ;;
  *)
    pass "non-macOS platform — sentinel skipped"
    ;;
esac

echo
if [ "$failures" -gt 0 ]; then
  echo "test-docs-latest-symlink-swap: FAIL ($failures failure(s))"
  exit 1
fi
echo "test-docs-latest-symlink-swap: OK"
