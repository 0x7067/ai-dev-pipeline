#!/usr/bin/env bash
# Contract test: resuming after Phase B completes with RELEASE_ANSWER=reject
# leaves the local commit + annotated tag intact, removes the state file,
# and exits 0.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-release-resume-phase-b-complete-reject: SKIP (jq not installed)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test-release-resume-phase-b-complete-reject: SKIP (git not installed)"
  exit 0
fi

tmp="$(mktemp -d -t release-resume-reject.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/.claude-plugin" "$tmp/scripts/release/lib" "$tmp/scripts"

cat > "$tmp/.claude-plugin/plugin.json" <<'EOF'
{ "name": "x", "version": "0.2.0" }
EOF
cat > "$tmp/.claude-plugin/marketplace.json" <<'EOF'
{ "name": "x", "plugins": [ { "name": "x", "version": "0.2.0" } ] }
EOF
cat > "$tmp/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [0.2.0] - 2026-05-10

### Added

- Hello world.

## [0.1.0] - 2026-05-01

### Added

- Initial release.
EOF

ln -s "$REPO_ROOT/scripts/release/parse-changelog.sh"        "$tmp/scripts/release/parse-changelog.sh"
ln -s "$REPO_ROOT/scripts/release/parse-release-state.sh"    "$tmp/scripts/release/parse-release-state.sh"
ln -s "$REPO_ROOT/scripts/release/release.sh"                "$tmp/scripts/release/release.sh"
ln -s "$REPO_ROOT/scripts/release/lib/semver-core.sh"        "$tmp/scripts/release/lib/semver-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/changelog-core.sh"     "$tmp/scripts/release/lib/changelog-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/resume-core.sh"        "$tmp/scripts/release/lib/resume-core.sh"

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

( cd "$tmp" && git init -q -b main && git config user.email t@test && git config user.name t \
    && git add -A && git commit -q -m "chore(release): v0.2.0" \
    && git tag -a v0.2.0 -m "Release v0.2.0" )

initial_head="$(cd "$tmp" && git rev-parse HEAD)"

state_file="$(mktemp -t release-state-reject.XXXXXX.json)"
jq -n \
  --arg phase   "phase-b-complete" \
  --arg proposed "0.2.0" \
  --arg bump    "minor" \
  --arg current "0.1.0" \
  --arg tv      "0.2.0" \
  --arg tag     "v0.2.0" \
  '{phase:$phase, proposed:$proposed, bump:$bump, current:$current, target_version:$tv, tag:$tag}' \
  > "$state_file"

out="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE="$state_file" \
        RELEASE_ANSWER=reject \
        bash scripts/release/release.sh 2>&1)" && rc=0 || rc=$?

if (( rc == 0 )); then
  pass "resume reject at phase-b-complete exits 0"
else
  fail "resume reject unexpected rc=$rc; out=$out"
fi

if grep -q 'push declined' <<<"$out"; then
  pass "diagnostic 'push declined' printed"
else
  fail "missing 'push declined' diagnostic; out=$out"
fi

# Commit + tag still present.
final_head="$(cd "$tmp" && git rev-parse HEAD)"
if [[ "$initial_head" == "$final_head" ]]; then
  pass "HEAD unchanged"
else
  fail "HEAD changed: $initial_head -> $final_head"
fi
if ( cd "$tmp" && git rev-parse v0.2.0 >/dev/null 2>&1 ); then
  pass "tag v0.2.0 still present locally"
else
  fail "tag v0.2.0 disappeared"
fi

# State file removed.
if [[ -f "$state_file" ]]; then
  fail "state file not cleaned up: $state_file"
else
  pass "state file removed on terminal exit"
fi

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
