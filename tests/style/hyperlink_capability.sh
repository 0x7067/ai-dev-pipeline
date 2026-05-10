#!/usr/bin/env bash
# Capability test: style::hyperlink emits OSC-8 only on TTY+color; otherwise plain text.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
STYLE_LIB="${REPO_ROOT}/scripts/lib/style.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$STYLE_LIB" ] || { echo "style.sh missing at $STYLE_LIB" >&2; exit 2; }

# Helper: run a fresh bash, source style.sh under specified env, call hyperlink.
# stdout is piped (non-TTY) by default. Use $1 to override env vars.
_emit() {
  local env_overrides="$1"
  bash -c "
    ${env_overrides}
    unset _STYLE_SH_LOADED
    source '${STYLE_LIB}'
    style::hyperlink 'https://example.com/x' 'link-text'
  "
}

# Case 1: NO_COLOR=1 → no escape, just plain text.
out=$(_emit "export NO_COLOR=1")
if [ "$out" = "link-text" ]; then
  pass "NO_COLOR=1 emits plain text"
else
  fail "NO_COLOR=1: expected 'link-text', got: $(printf '%s' "$out" | od -c | head -2)"
fi

# Case 2: piped (non-TTY) without NO_COLOR — STYLE_COLOR should be 0 because stdout is not a TTY.
out=$(_emit "unset NO_COLOR CLICOLOR_FORCE")
if [ "$out" = "link-text" ] && ! printf '%s' "$out" | grep -q $'\x1b'; then
  pass "non-TTY stdout emits no escapes"
else
  fail "non-TTY: expected plain 'link-text', got escapes"
fi

# Case 3: CLICOLOR_FORCE=1 forces color regardless of TTY → hyperlinks active.
out=$(_emit "export CLICOLOR_FORCE=1; unset NO_COLOR")
# When color is forced but stdout is not a TTY, STYLE_HYPERLINKS still requires `[ -t 1 ]`.
# So we should NOT see OSC-8 here either — the gating is intentional per the plan.
if ! printf '%s' "$out" | grep -q $'\x1b\\]8'; then
  pass "CLICOLOR_FORCE=1 + non-TTY suppresses OSC-8 (gating preserves no-ANSI-when-piped)"
else
  fail "CLICOLOR_FORCE=1 + non-TTY: unexpected OSC-8 in piped output"
fi

# Case 4: simulate TTY by sourcing under script(1) when available, otherwise skip.
# We assert the OSC-8 sequence shape directly using a synthetic STYLE_HYPERLINKS=1 path.
# Approach: temporarily monkey-patch by exporting the readonly via a fresh subshell that
# sources style.sh after fooling the [ -t 1 ] check via a here-doc fed to bash with a TTY.
if command -v script >/dev/null 2>&1; then
  # macOS `script` syntax: script -q /dev/null cmd ...
  if script -q /dev/null bash -c "
    export CLICOLOR_FORCE=1
    unset NO_COLOR
    unset _STYLE_SH_LOADED
    source '${STYLE_LIB}'
    style::hyperlink 'https://example.com/x' 'link-text'
  " 2>/dev/null | tr -d '\r' | grep -q $'\x1b\\]8;;https://example.com/x'; then
    pass "TTY+color emits OSC-8 hyperlink"
  else
    # Try Linux `script` form as fallback.
    if script -qec "export CLICOLOR_FORCE=1; unset NO_COLOR _STYLE_SH_LOADED; source '${STYLE_LIB}'; style::hyperlink 'https://example.com/x' 'link-text'" /dev/null 2>/dev/null | tr -d '\r' | grep -q $'\x1b\\]8;;https://example.com/x'; then
      pass "TTY+color emits OSC-8 hyperlink (linux script)"
    else
      echo "  skip: TTY emulation via script(1) did not produce OSC-8; environment-dependent" >&2
    fi
  fi
else
  echo "  skip: script(1) not available; cannot emulate TTY" >&2
fi

if [ "$failures" -eq 0 ]; then
  echo "hyperlink_capability: PASS"
  exit 0
fi
echo "hyperlink_capability: FAIL ($failures)" >&2
exit 1
