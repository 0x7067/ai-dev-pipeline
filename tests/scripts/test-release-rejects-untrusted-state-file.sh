#!/usr/bin/env bash
# Boundary test (I-statepath): on resume, RELEASE_STATE_FILE must resolve
# under $TMPDIR or /tmp/. An untrusted path (e.g. /etc/foo) is rejected
# before any state read happens.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-release-rejects-untrusted-state-file: SKIP (jq not installed)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test-release-rejects-untrusted-state-file: SKIP (git not installed)"
  exit 0
fi

tmp="$(mktemp -d -t release-statepath.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/.claude-plugin" "$tmp/scripts/release/lib" "$tmp/scripts"
cat > "$tmp/.claude-plugin/plugin.json" <<'EOF'
{ "name": "x", "version": "0.1.0" }
EOF
cat > "$tmp/.claude-plugin/marketplace.json" <<'EOF'
{ "name": "x", "plugins": [ { "name": "x", "version": "0.1.0" } ] }
EOF
cat > "$tmp/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- placeholder
EOF

ln -s "$REPO_ROOT/scripts/release/parse-changelog.sh"     "$tmp/scripts/release/parse-changelog.sh"
ln -s "$REPO_ROOT/scripts/release/release.sh"             "$tmp/scripts/release/release.sh"
ln -s "$REPO_ROOT/scripts/release/lib/semver-core.sh"     "$tmp/scripts/release/lib/semver-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/changelog-core.sh"  "$tmp/scripts/release/lib/changelog-core.sh"

( cd "$tmp" && git init -q && git config user.email t@test && git config user.name t \
    && git add -A && git commit -q -m initial )

# Case 1: untrusted path under /etc — must be rejected.
out1="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE=/etc/release-state-bogus.json \
    RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)" && rc1=0 || rc1=$?

if (( rc1 == 1 )); then
  pass "untrusted path rejected with rc=1"
else
  fail "expected rc=1 for untrusted path; got rc=$rc1 out=$out1"
fi

if grep -q 'RELEASE_STATE_FILE' <<<"$out1" && grep -q 'must be under' <<<"$out1"; then
  pass "structured rejection mentions RELEASE_STATE_FILE and 'must be under'"
else
  fail "rejection lacks expected structure; out=$out1"
fi

# Case 2: relative path — also rejected.
out2="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE=relative/path.json \
    RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)" && rc2=0 || rc2=$?
if (( rc2 == 1 )) && grep -q 'absolute path' <<<"$out2"; then
  pass "relative path rejected"
else
  fail "relative path not rejected as expected; rc=$rc2 out=$out2"
fi

# Case 3: empty value on resume — rejected.
out3="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE= \
    RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)" && rc3=0 || rc3=$?
if (( rc3 == 1 )) && grep -q 'empty' <<<"$out3"; then
  pass "empty value rejected"
else
  fail "empty value not rejected; rc=$rc3 out=$out3"
fi

# Case 4: positive — path under $TMPDIR points at a non-existent file. The
# boundary parser passes; the next check ("state file missing or
# unreadable") fires. Confirms the parser is UPSTREAM of file existence.
tmpdir="${TMPDIR:-/tmp}"
good_path="${tmpdir%/}/release-state-does-not-exist-$$.json"
out4="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE="$good_path" \
    RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)" && rc4=0 || rc4=$?
if (( rc4 == 1 )) && grep -q 'missing or unreadable' <<<"$out4"; then
  pass "valid \$TMPDIR path passes parser, hits file-existence check next"
else
  fail "expected file-existence failure for good \$TMPDIR path; rc=$rc4 out=$out4"
fi

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
