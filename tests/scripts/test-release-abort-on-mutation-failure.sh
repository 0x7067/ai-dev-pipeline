#!/usr/bin/env bash
# Contract test (I-atomic): when Phase B mutations fail mid-sequence,
# release.sh exits non-zero BEFORE creating a `chore(release):` commit or
# `v*` tag, and prints the structured recovery hint on stderr.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-release-abort-on-mutation-failure: SKIP (jq not installed)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test-release-abort-on-mutation-failure: SKIP (git not installed)"
  exit 0
fi

tmp="$(mktemp -d -t release-atomicity.XXXXXX)"
cleanup() {
  # Restore writability so rm -rf can clean up.
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp"
}
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

- Hello world.

## [0.1.0] - 2026-05-01

### Added

- Initial release.
EOF

ln -s "$REPO_ROOT/scripts/release/parse-changelog.sh"     "$tmp/scripts/release/parse-changelog.sh"
ln -s "$REPO_ROOT/scripts/release/parse-release-state.sh" "$tmp/scripts/release/parse-release-state.sh"
ln -s "$REPO_ROOT/scripts/release/release.sh"             "$tmp/scripts/release/release.sh"
ln -s "$REPO_ROOT/scripts/release/lib/semver-core.sh"     "$tmp/scripts/release/lib/semver-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/changelog-core.sh"  "$tmp/scripts/release/lib/changelog-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/resume-core.sh"     "$tmp/scripts/release/lib/resume-core.sh"
ln -s "$REPO_ROOT/scripts/check-plugin-version-sync.sh"   "$tmp/scripts/check-plugin-version-sync.sh"
ln -s "$REPO_ROOT/scripts/harness-lib.sh"                 "$tmp/scripts/harness-lib.sh"

cat > "$tmp/scripts/validate-claude-config.sh"  <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp/scripts/run-verification-gates.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp/scripts/smoke-bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/scripts/"*.sh

( cd "$tmp" && git init -q && git config user.email t@test && git config user.name t \
    && git add -A && git commit -q -m initial )

# Phase A — capture state file.
out_a="$(cd "$tmp" && bash scripts/release/release.sh 2>&1)" || true
state_file="$(grep -oE 'RELEASE_STATE_FILE=[^ ]+' <<<"$out_a" | head -1 | cut -d= -f2)"
if [[ -z "$state_file" ]]; then
  fail "phase A did not emit RELEASE_STATE_FILE"
  exit 1
fi

# Force mid-sequence mutation failure by making the manifest directory
# read+execute only. `mv` over an existing file in a read-only directory
# fails with EACCES, which propagates through bump_json_version under
# `set -e`.
chmod 0555 "$tmp/.claude-plugin"

out_b="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE="$state_file" \
    RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)" && rc_b=0 || rc_b=$?

# Restore for inspection + later cleanup.
chmod 0755 "$tmp/.claude-plugin"

if (( rc_b != 0 )); then
  pass "Phase B aborted with rc=$rc_b on mutation failure"
else
  fail "Phase B unexpectedly returned 0 with read-only manifest dir; out=$out_b"
fi

if grep -q 'mutation aborted; recover with:' <<<"$out_b"; then
  pass "recovery hint printed to stderr"
else
  fail "recovery hint missing; out=$out_b"
fi

# No release commit landed.
if ( cd "$tmp" && git log --oneline ) | grep -q 'chore(release):'; then
  fail "release commit was created despite mutation failure"
else
  pass "no chore(release) commit was created"
fi

# No tag was created.
if ( cd "$tmp" && git tag -l 'v*' ) | grep -q '.'; then
  fail "v* tag was created despite mutation failure"
else
  pass "no v* tag was created"
fi

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
