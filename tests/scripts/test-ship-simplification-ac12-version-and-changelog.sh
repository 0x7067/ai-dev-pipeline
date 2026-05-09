#!/usr/bin/env bash
# AC12: plugin.json and .claude-plugin/plugin.json versions match
# (scripts/check-plugin-version-sync.sh exits 0); CHANGELOG records the
# breaking removal of `adaptive`.
#
# The version-sync part already passes today (regression guard). The
# CHANGELOG entry is brand-new and currently absent — that assertion
# is the one expected to fail on the pre-implementation tree.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SYNC_SCRIPT="${REPO_ROOT}/scripts/check-plugin-version-sync.sh"
CHANGELOG="${REPO_ROOT}/CHANGELOG.md"
PLUGIN_JSON="${REPO_ROOT}/plugin.json"
PLUGIN_PLUGIN_JSON="${REPO_ROOT}/.claude-plugin/plugin.json"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# 1. Plugin version sync gate.
if [ -x "$SYNC_SCRIPT" ] || [ -f "$SYNC_SCRIPT" ]; then
  if (cd "$REPO_ROOT" && bash "$SYNC_SCRIPT" >/tmp/vs.out 2>&1); then
    pass "plugin version sync gate exits 0"
  else
    fail "plugin version sync gate failed (AC12)"
    sed -e 's/^/    | /' /tmp/vs.out >&2 || true
  fi
else
  fail "scripts/check-plugin-version-sync.sh missing"
fi

# 2. CHANGELOG.md exists and records the breaking removal of adaptive.
if [ ! -f "$CHANGELOG" ]; then
  fail "CHANGELOG.md does not exist (AC12)"
elif grep -qiE 'breaking' "$CHANGELOG" \
     && grep -qE '\badaptive\b' "$CHANGELOG" \
     && grep -qiE 'remov(e|ed|al)' "$CHANGELOG"; then
  pass "CHANGELOG.md records breaking removal of adaptive"
else
  fail "CHANGELOG.md does not record the breaking removal of adaptive (AC12)"
fi

# 3. CHANGELOG mentions the introduction of fast as default and config_only.
if [ -f "$CHANGELOG" ]; then
  if grep -qE '\bfast\b' "$CHANGELOG" && grep -qE '\bconfig_only\b' "$CHANGELOG"; then
    pass "CHANGELOG records introduction of fast + config_only"
  else
    fail "CHANGELOG does not record introduction of fast / config_only (AC12)"
  fi
fi

# 4. Version bump: post-simplification version must NOT equal current
#    pre-implementation 0.8.0 (sanity guard against forgetting to bump).
if [ -f "$PLUGIN_JSON" ]; then
  cur_version="$(grep -E '"version"' "$PLUGIN_JSON" | head -n1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  if [ "$cur_version" = "0.8.0" ]; then
    fail "plugin.json version still 0.8.0 — must bump for breaking change (AC12)"
  else
    pass "plugin.json version bumped beyond 0.8.0 (got $cur_version)"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo "test-ac12-version-and-changelog: FAILED ($failures)" >&2
  exit 1
fi
echo "test-ac12-version-and-changelog: OK"
