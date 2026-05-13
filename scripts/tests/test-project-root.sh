#!/usr/bin/env bash
# test-project-root.sh — boundary parser tests for aidp_resolve_project_root.
#
# Contract under test (scripts/lib/project-root.sh):
#   1. CLAUDE_PROJECT_DIR set to a real directory → echoes its canonical path.
#   2. CLAUDE_PROJECT_DIR unset → falls back to $(pwd).
#   3. CLAUDE_PROJECT_DIR set to a non-existent path → fails closed
#      (non-zero exit, empty stdout).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
LIB="${SCRIPT_DIR}/../lib/project-root.sh"

if [ ! -f "$LIB" ]; then
  echo "test-project-root: ERROR: missing $LIB" >&2
  exit 1
fi

fails=0
pass() { printf '  ok  %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

# Pick a directory that exists on every host we care about. /tmp on
# macOS resolves to /private/tmp via pwd -P; the test asserts the
# canonical form, not the input form.
real_dir="$(cd /tmp >/dev/null 2>&1 && pwd -P)"

# Test 1: explicit CLAUDE_PROJECT_DIR.
out="$(CLAUDE_PROJECT_DIR=/tmp bash -c "source '$LIB' && aidp_resolve_project_root" 2>/dev/null)"
rc=$?
if [ "$rc" = 0 ] && [ "$out" = "$real_dir" ]; then
  pass "CLAUDE_PROJECT_DIR=/tmp → $real_dir"
else
  fail "CLAUDE_PROJECT_DIR=/tmp: rc=$rc out='$out' (want '$real_dir')"
fi

# Test 2: fallback to $(pwd).
out="$(cd /tmp && unset CLAUDE_PROJECT_DIR && bash -c "source '$LIB' && aidp_resolve_project_root" 2>/dev/null)"
rc=$?
if [ "$rc" = 0 ] && [ "$out" = "$real_dir" ]; then
  pass "unset CLAUDE_PROJECT_DIR → \$(pwd)"
else
  fail "fallback: rc=$rc out='$out' (want '$real_dir')"
fi

# Test 3: fail-closed on non-existent dir.
out="$(CLAUDE_PROJECT_DIR=/definitely/does/not/exist/aidp bash -c "source '$LIB' && aidp_resolve_project_root" 2>/dev/null)"
rc=$?
if [ "$rc" != 0 ] && [ -z "$out" ]; then
  pass "non-existent dir → fail closed (rc=$rc, empty stdout)"
else
  fail "non-existent dir: rc=$rc out='$out' (want non-zero + empty)"
fi

# Test 4: idempotent source guard — sourcing twice must not error.
if bash -c "source '$LIB' && source '$LIB' && aidp_resolve_project_root >/dev/null" </dev/null 2>/dev/null; then
  pass "idempotent source guard"
else
  fail "double-source errored"
fi

# Test 5: artifacts root for a consumer project (no plugin manifest) →
# <root>/docs/aidp.
tmpdir="$(mktemp -d)"
out="$(bash -c "source '$LIB' && aidp_resolve_artifacts_root '$tmpdir'" 2>/dev/null)"
rc=$?
expected="$(cd "$tmpdir" && pwd -P)/docs/aidp"
if [ "$rc" = 0 ] && [ "$out" = "$expected" ]; then
  pass "consumer root → docs/aidp"
else
  fail "consumer root: rc=$rc out='$out' (want '$expected')"
fi

# Test 6a: plugin checkout with matching name STILL resolves to docs/aidp.
# The legacy plugin-self-dev exception was removed — every caller, including
# the plugin's own checkout, now uses the single docs/aidp layout. The
# presence of .claude-plugin/plugin.json is no longer read by the resolver.
mkdir -p "$tmpdir/.claude-plugin"
printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' > "$tmpdir/.claude-plugin/plugin.json"
out="$(bash -c "source '$LIB' && aidp_resolve_artifacts_root '$tmpdir'" 2>/dev/null)"
rc=$?
expected="$(cd "$tmpdir" && pwd -P)/docs/aidp"
if [ "$rc" = 0 ] && [ "$out" = "$expected" ]; then
  pass "plugin checkout (name=ai-dev-pipeline) → docs/aidp (no legacy exception)"
else
  fail "plugin checkout: rc=$rc out='$out' (want '$expected')"
fi

# Test 6b: another plugin (different name) — same result; plugin.json is irrelevant.
printf '{"name":"some-other-plugin","version":"1.0.0"}\n' > "$tmpdir/.claude-plugin/plugin.json"
out="$(bash -c "source '$LIB' && aidp_resolve_artifacts_root '$tmpdir'" 2>/dev/null)"
rc=$?
expected="$(cd "$tmpdir" && pwd -P)/docs/aidp"
if [ "$rc" = 0 ] && [ "$out" = "$expected" ]; then
  pass "foreign plugin → docs/aidp (treated as consumer)"
else
  fail "foreign plugin: rc=$rc out='$out' (want '$expected')"
fi
rm -rf "$tmpdir"

# Test 7: artifacts root fails closed on missing dir.
out="$(bash -c "source '$LIB' && aidp_resolve_artifacts_root /nope/aidp/nope" 2>/dev/null)"
rc=$?
if [ "$rc" != 0 ] && [ -z "$out" ]; then
  pass "artifacts root: missing dir → fail closed"
else
  fail "artifacts root missing dir: rc=$rc out='$out'"
fi

if [ "$fails" -gt 0 ]; then
  echo "test-project-root: FAILED ($fails)" >&2
  exit 1
fi
echo "test-project-root: OK"
