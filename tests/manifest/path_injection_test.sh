#!/usr/bin/env bash
# Contract test: parse-manifest.sh rejects path-injection in artifacts[].path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-manifest.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

tmpdir=$(mktemp -d -t manifest-pathinj.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

write_manifest_with_path() {
  local dir="$1" raw_path="$2"
  mkdir -p "$dir"
  cat > "$dir/manifest.json" <<EOF
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[{"kind":"other","path":"${raw_path}","sha256":"0000000000000000000000000000000000000000000000000000000000000000","bytes":1}]}
EOF
}

expect_reject_path() {
  local label="$1" dir="$2"
  if bash "$PARSER" "$dir/manifest.json" >/dev/null 2>&1; then
    fail "$label: parser accepted dangerous path"
  else
    pass "$label"
  fi
}

# 1. Lexical .. traversal.
write_manifest_with_path "$tmpdir/p1" "../etc/passwd"
expect_reject_path "rejects ../etc/passwd" "$tmpdir/p1"

# 2. Embedded .. segment.
write_manifest_with_path "$tmpdir/p2" "research/../../escape.md"
expect_reject_path "rejects embedded .. segment" "$tmpdir/p2"

# 3. Absolute path.
write_manifest_with_path "$tmpdir/p3" "/etc/passwd"
expect_reject_path "rejects absolute path" "$tmpdir/p3"

# 4. Backslash sneak.
write_manifest_with_path "$tmpdir/p4" "research\\..\\..\\escape.md"
expect_reject_path "rejects backslash" "$tmpdir/p4"

# 5. Symlink-escape: a symlink under run-dir whose target is outside.
mkdir -p "$tmpdir/p5"
mkdir -p "$tmpdir/outside"
echo "secret" > "$tmpdir/outside/leak.txt"
ln -s "$tmpdir/outside/leak.txt" "$tmpdir/p5/leak.md"
write_manifest_with_path "$tmpdir/p5" "leak.md"
expect_reject_path "rejects symlink-escape under run-dir" "$tmpdir/p5"

# 6. NUL byte in file should be rejected at the file-content level.
mkdir -p "$tmpdir/p6"
printf '{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[\x00]}' > "$tmpdir/p6/manifest.json"
if bash "$PARSER" "$tmpdir/p6/manifest.json" >/dev/null 2>&1; then
  fail "rejects NUL byte: parser accepted"
else
  pass "rejects NUL byte"
fi

# 7. Sanity: a benign relative path under run-dir is accepted.
mkdir -p "$tmpdir/p7"
write_manifest_with_path "$tmpdir/p7" "current-plan.md"
echo "ok" > "$tmpdir/p7/current-plan.md"
if bash "$PARSER" "$tmpdir/p7/manifest.json" >/dev/null 2>&1; then
  pass "accepts benign current-plan.md"
else
  fail "accepts benign current-plan.md: parser rejected"
fi

if [ "$failures" -gt 0 ]; then
  echo "path_injection_test: FAILED ($failures)" >&2
  exit 1
fi
echo "path_injection_test: OK"
