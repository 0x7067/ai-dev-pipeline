#!/usr/bin/env bash
# Contract test: after a simulated release (Phase B mutations only) on a
# throwaway temp repo, the three version strings move together (I1
# lockstep) and `scripts/check-plugin-version-sync.sh` exits 0.
#
# This test bypasses the gate trio (validator + verification + smoke) by
# stubbing those scripts inside the temp repo so the orchestrator's
# decision/mutation path can be exercised in isolation.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-release-version-lockstep: SKIP (jq not installed)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test-release-version-lockstep: SKIP (git not installed)"
  exit 0
fi

tmp="$(mktemp -d -t release-lockstep.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# Construct a minimal fake repo with just enough surface for release.sh to
# operate on. The orchestrator changes directory to its own repo root via
# the script-dir resolution; we sidestep that by symlinking the release/
# tree and invoking from within the temp dir using a wrapper that chdirs
# the temp first.
mkdir -p "$tmp/.claude-plugin" "$tmp/scripts/release/lib" "$tmp/scripts" "$tmp/.git"

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

# Symlink real scripts (release/, parse-changelog.sh, etc.) into temp.
ln -s "$REPO_ROOT/scripts/release/parse-changelog.sh"     "$tmp/scripts/release/parse-changelog.sh"
ln -s "$REPO_ROOT/scripts/release/parse-release-state.sh" "$tmp/scripts/release/parse-release-state.sh"
ln -s "$REPO_ROOT/scripts/release/release.sh"             "$tmp/scripts/release/release.sh"
ln -s "$REPO_ROOT/scripts/release/lib/semver-core.sh"     "$tmp/scripts/release/lib/semver-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/changelog-core.sh"  "$tmp/scripts/release/lib/changelog-core.sh"
ln -s "$REPO_ROOT/scripts/release/lib/resume-core.sh"     "$tmp/scripts/release/lib/resume-core.sh"
ln -s "$REPO_ROOT/scripts/check-plugin-version-sync.sh" "$tmp/scripts/check-plugin-version-sync.sh"
ln -s "$REPO_ROOT/scripts/harness-lib.sh"               "$tmp/scripts/harness-lib.sh"

# Stub gate scripts that release.sh shells out to (so we don't run the
# real gate suite in this tiny harness).
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

# Init git so the orchestrator's status/commit/tag calls succeed. The real
# release.sh resolves REPO_ROOT relative to the script's own location, so
# we bind-mount the temp dir as the script's parent by running the
# orchestrator after `cd "$tmp"` AND overriding REPO_ROOT via the script's
# self-resolution: since release.sh resolves REPO_ROOT from $SCRIPT_DIR/..,
# the symlinked path's `..` lands in the temp tree.
( cd "$tmp" && git init -q && git config user.email t@test && git config user.name t && git add -A && git commit -q -m initial )

# Exercise Phase A: expect a HALT (exit 75) with a version-confirm payload.
out_a="$(cd "$tmp" && bash scripts/release/release.sh 2>&1)"
rc_a=$?
if (( rc_a == 75 )) && grep -q 'kind=version-confirm' <<<"$out_a"; then
  pass "phase A halts on version-confirm with rc=75"
else
  fail "phase A unexpected rc=$rc_a out=$out_a"
fi
proposed="$(grep -oE 'proposed=[0-9.]+' <<<"$out_a" | head -1 | cut -d= -f2)"
state_file="$(grep -oE 'RELEASE_STATE_FILE=[^ ]+' <<<"$out_a" | head -1 | cut -d= -f2)"
[[ "$proposed" == "0.2.0" ]] && pass "phase A proposes 0.2.0 (Added -> minor)" || fail "phase A proposed=$proposed"

# Phase B with approve.
out_b="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_STATE_FILE="$state_file" RELEASE_ANSWER=approve bash scripts/release/release.sh 2>&1)"
rc_b=$?
if (( rc_b == 75 )) && grep -q 'kind=push-confirm' <<<"$out_b"; then
  pass "phase B halts on push-confirm with rc=75"
else
  fail "phase B unexpected rc=$rc_b out=$out_b"
fi

# Lockstep invariant: both manifests now hold 0.2.0.
plugin_v="$(jq -r '.version' "$tmp/.claude-plugin/plugin.json")"
mp_v="$(jq -r '.plugins[0].version' "$tmp/.claude-plugin/marketplace.json")"
if [[ "$plugin_v" == "0.2.0" && "$mp_v" == "0.2.0" ]]; then
  pass "I1 lockstep: plugin.json=$plugin_v marketplace.json=$mp_v"
else
  fail "I1 lockstep broken: plugin=$plugin_v marketplace=$mp_v"
fi

# CHANGELOG: dated header present, fresh empty Unreleased on top.
if grep -q "^## \[0.2.0\] - " "$tmp/CHANGELOG.md"; then
  pass "I6: dated section header written"
else
  fail "I6: dated section header missing"
fi
if head -10 "$tmp/CHANGELOG.md" | grep -q "^## \[Unreleased\]"; then
  pass "D2: fresh [Unreleased] placeholder restored"
else
  fail "D2: [Unreleased] placeholder missing"
fi

# Annotated tag created with bullet body.
tag_msg="$(cd "$tmp" && git tag -l --format='%(contents)' v0.2.0 2>/dev/null || true)"
if grep -q '^Release v0.2.0$' <<<"$tag_msg" && grep -q 'Hello world' <<<"$tag_msg"; then
  pass "D3: annotated tag body contains release header + bullet"
else
  fail "D3: tag body missing/malformed: $tag_msg"
fi

# Plugin version-sync agreement.
( cd "$tmp" && bash scripts/check-plugin-version-sync.sh ) >/dev/null 2>&1 \
  && pass "check-plugin-version-sync.sh exits 0 after release" \
  || fail "check-plugin-version-sync.sh non-zero after release"

# Phase C (push approve, dry-run via reject path — we don't have a remote).
# Reject the push; expect rc=0 and no push attempted.
state_file2="$(grep -oE 'RELEASE_STATE_FILE=[^ ]+' <<<"$out_b" | head -1 | cut -d= -f2)"
out_c="$(cd "$tmp" && env RELEASE_RESUME=1 RELEASE_PHASE=push RELEASE_STATE_FILE="$state_file2" RELEASE_ANSWER=reject bash scripts/release/release.sh 2>&1)"
rc_c=$?
if (( rc_c == 0 )) && grep -q 'push declined' <<<"$out_c"; then
  pass "phase C reject leaves commit + tag local"
else
  fail "phase C unexpected rc=$rc_c out=$out_c"
fi

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
