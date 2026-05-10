#!/usr/bin/env bash
# Contract test: resuming after Phase B completes (state file records
# phase=phase-b-complete) with RELEASE_ANSWER=approve pushes HEAD + tag
# WITHOUT re-running any mutation (no second commit, no re-tag attempt).
#
# Reproduces the bug fixed by this plan: previously, resume without
# RELEASE_PHASE=push re-entered Phase B from scratch and aborted on
# `tag vX.Y.Z already exists`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test-release-resume-phase-b-complete-approve: SKIP (jq not installed)"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "test-release-resume-phase-b-complete-approve: SKIP (git not installed)"
  exit 0
fi

tmp="$(mktemp -d -t release-resume-approve.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/.claude-plugin" "$tmp/scripts/release/lib" "$tmp/scripts"

# Manifests already AT the released version (Phase B already ran).
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

# Provide a fake `git` that records pushes and rejects everything else
# destructive. The orchestrator should ONLY invoke `git push` and
# `git rev-parse v0.2.0` on this branch (plus the upfront `git status`
# performed only on a fresh run, not on resume).
fake_bin="$tmp/fake-bin"
mkdir -p "$fake_bin"
push_log="$tmp/push.log"
cat > "$fake_bin/git" <<EOF
#!/usr/bin/env bash
real_git=\$(PATH="\${PATH#$fake_bin:}" command -v git)
case "\$1" in
  push)
    printf 'push: %s\n' "\$*" >> "$push_log"
    exit 0
    ;;
  commit|tag)
    if [[ "\$1" == "tag" ]]; then
      case "\$2" in
        -a|--annotate|--list|-l|--format*|-d)
          # delegate read-only / list / delete-not-used variants
          ;;
        *)
          ;;
      esac
    fi
    if [[ "\$1" == "commit" || ( "\$1" == "tag" && "\$2" == "-a" ) ]]; then
      printf 'forbidden-mutation: %s\n' "\$*" >> "$tmp/forbidden.log"
      exit 99
    fi
    exec "\$real_git" "\$@"
    ;;
  *)
    exec "\$real_git" "\$@"
    ;;
esac
EOF
chmod +x "$fake_bin/git"

# Construct a state file as if Phase B had just completed.
state_file="$(mktemp -t release-state-approve.XXXXXX.json)"
jq -n \
  --arg phase   "phase-b-complete" \
  --arg proposed "0.2.0" \
  --arg bump    "minor" \
  --arg current "0.1.0" \
  --arg tv      "0.2.0" \
  --arg tag     "v0.2.0" \
  '{phase:$phase, proposed:$proposed, bump:$bump, current:$current, target_version:$tv, tag:$tag}' \
  > "$state_file"

out="$(cd "$tmp" && env PATH="$fake_bin:$PATH" \
        RELEASE_RESUME=1 RELEASE_STATE_FILE="$state_file" \
        RELEASE_ANSWER=approve \
        bash scripts/release/release.sh 2>&1)" && rc=0 || rc=$?

if (( rc == 0 )); then
  pass "resume approve at phase-b-complete exits 0"
else
  fail "resume approve unexpected rc=$rc; out=$out"
fi

# Push must have been attempted twice (HEAD + tag).
if [[ -s "$push_log" ]] && grep -q 'origin v0.2.0' "$push_log"; then
  pass "git push origin v0.2.0 invoked"
else
  fail "expected push to origin v0.2.0; push_log=$(cat "$push_log" 2>/dev/null)"
fi

# No re-mutation: no second commit, no re-tag.
if [[ -s "$tmp/forbidden.log" ]]; then
  fail "forbidden mutation invoked: $(cat "$tmp/forbidden.log")"
else
  pass "no commit / tag re-issued during push phase"
fi

# HEAD did not advance.
final_head="$(cd "$tmp" && git rev-parse HEAD)"
if [[ "$initial_head" == "$final_head" ]]; then
  pass "HEAD unchanged across resume"
else
  fail "HEAD advanced: $initial_head -> $final_head"
fi

# State file removed on terminal exit.
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
