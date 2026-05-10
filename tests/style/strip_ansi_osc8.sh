#!/usr/bin/env bash
# Regression test: style::strip_ansi removes OSC 8 hyperlink sequences AND CSI/SGR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
STYLE_LIB="${REPO_ROOT}/scripts/lib/style.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$STYLE_LIB" ] || { echo "style.sh missing at $STYLE_LIB" >&2; exit 2; }

# Helper: feed input to style::strip_ansi via fresh bash.
_strip() {
  bash -c "
    unset _STYLE_SH_LOADED
    source '${STYLE_LIB}'
    style::strip_ansi
  "
}

# Case 1: OSC-8 hyperlink with ESC\ terminator → keeps only the link text.
# Format: ESC]8;;URL ESC\ TEXT ESC]8;; ESC\
input=$'\x1b]8;;https://example.com\x1b\\link-text\x1b]8;;\x1b\\'
out=$(printf '%s' "$input" | _strip)
if [ "$out" = "link-text" ]; then
  pass "OSC-8 with ESC\\ terminator stripped"
else
  fail "OSC-8 ESC\\ strip: expected 'link-text', got: $(printf '%s' "$out" | od -c | head -2)"
fi

# Case 2: OSC-8 with BEL (\a) terminator.
input=$'\x1b]8;;https://example.com\x07link-text\x1b]8;;\x07'
out=$(printf '%s' "$input" | _strip)
if [ "$out" = "link-text" ]; then
  pass "OSC-8 with BEL terminator stripped"
else
  fail "OSC-8 BEL strip: expected 'link-text', got: $(printf '%s' "$out" | od -c | head -2)"
fi

# Case 3: combined CSI/SGR + OSC-8.
input=$'\x1b[32m\x1b]8;;https://x\x1b\\green-link\x1b]8;;\x1b\\\x1b[0m'
out=$(printf '%s' "$input" | _strip)
if [ "$out" = "green-link" ]; then
  pass "combined CSI + OSC-8 stripped"
else
  fail "combined strip: expected 'green-link', got: $(printf '%s' "$out" | od -c | head -2)"
fi

# Case 4: plain text passes through unchanged.
input="no escapes here"
out=$(printf '%s' "$input" | _strip)
if [ "$out" = "$input" ]; then
  pass "plain text unchanged"
else
  fail "plain text mutated: got '$out'"
fi

if [ "$failures" -eq 0 ]; then
  echo "strip_ansi_osc8: PASS"
  exit 0
fi
echo "strip_ansi_osc8: FAIL ($failures)" >&2
exit 1
