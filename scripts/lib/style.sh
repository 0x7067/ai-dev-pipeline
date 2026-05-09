# style.sh — shared output style helpers for plugin shell surfaces.
#
# This file is sourced, not executed. It provides a small set of
# capability-aware emitters that produce a consistent set of status glyphs,
# colors, and section dividers across `/ship`, gate runners, and other
# stdout-only shell surfaces.
#
# FC/IS placement: shell-only. No business logic. The capability detection
# block parses environment variables ONCE into the readonly globals
# STYLE_COLOR (0|1), STYLE_UNICODE (0|1), and STYLE_USE_GUM (0|1). Emitters
# only consume these parsed flags — they never re-read raw env values.
#
# Usage:
#   source "${BASH_SOURCE%/*}/lib/style.sh"
#   style::header "Verification gates"
#   style::step   "running typecheck"
#   style::ok     "typecheck passed"
#   style::warn   "skipped: no contract suite configured"
#   style::fail   "lint failed (rc=2)"
#   style::info   "log written to docs/runs/.../verify.log"
#   style::dim    "elapsed 3s"
#   style::retry  "lint retry 1/2"
#   style::join   "read-only gates joined (rc=0,0,0)"
#   style::rule
#   style::box "Release auto-approved"
#
# Stripping ANSI for redirection into docs:
#   style::ok "done" | style::strip_ansi >> some.log
#
# Environment overrides honored:
#   NO_COLOR         — any non-empty value disables color
#   CLICOLOR=0       — disables color
#   CLICOLOR_FORCE=1 — forces color even when stdout is not a TTY
#   AIDP_USE_GUM     — unset/empty=auto, 0=force off, 1=require gum present
#   LANG/LC_ALL/LC_CTYPE — *UTF-8* enables Unicode glyph set
#
# Conventions:
#   - Sourceable, not executable. No top-level side effects beyond setting
#     readonly globals and defining functions.
#   - Safe under `set -euo pipefail`: every env read is `${VAR:-}`-guarded
#     and emitters return 0 explicitly so they don't trip `set -e`.
#   - Idempotent: sourcing twice is a no-op (guarded by _STYLE_SH_LOADED).

# ---------------------------------------------------------------------------
# Idempotency guard
# ---------------------------------------------------------------------------
[[ -n "${_STYLE_SH_LOADED:-}" ]] && return 0
_STYLE_SH_LOADED=1

# ---------------------------------------------------------------------------
# Boundary: parse env into typed capability flags
# ---------------------------------------------------------------------------

# _style::detect_color — parse env into 0|1; echoes the result.
_style::detect_color() {
  if [[ -n "${NO_COLOR:-}" ]]; then
    printf '0\n'; return 0
  fi
  if [[ "${CLICOLOR_FORCE:-}" = "1" ]]; then
    printf '1\n'; return 0
  fi
  if [[ "${CLICOLOR:-}" = "0" ]]; then
    printf '0\n'; return 0
  fi
  if [[ -t 1 ]]; then
    printf '1\n'; return 0
  fi
  printf '0\n'
  return 0
}

# _style::detect_unicode — parse locale env into 0|1; echoes the result.
_style::detect_unicode() {
  local probe="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
  case "${probe}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) printf '1\n' ;;
    *)                              printf '0\n' ;;
  esac
  return 0
}

# _style::detect_gum — 0|1 echoed; honors AIDP_USE_GUM.
# Requires both color and unicode to be enabled before considering gum.
_style::detect_gum() {
  local color="$1"
  local unicode="$2"
  local pref="${AIDP_USE_GUM:-}"

  if [[ "$pref" = "0" ]]; then
    printf '0\n'; return 0
  fi
  if [[ "$color" != "1" || "$unicode" != "1" ]]; then
    printf '0\n'; return 0
  fi
  if command -v gum >/dev/null 2>&1; then
    printf '1\n'; return 0
  fi
  if [[ "$pref" = "1" ]]; then
    printf 'style: AIDP_USE_GUM=1 but `gum` not on PATH; falling back to plain emitters\n' >&2
  fi
  printf '0\n'
  return 0
}

STYLE_COLOR="$(_style::detect_color)"
STYLE_UNICODE="$(_style::detect_unicode)"
STYLE_USE_GUM="$(_style::detect_gum "$STYLE_COLOR" "$STYLE_UNICODE")"
readonly STYLE_COLOR STYLE_UNICODE STYLE_USE_GUM

# ---------------------------------------------------------------------------
# Internal palette (resolved once from STYLE_COLOR)
# ---------------------------------------------------------------------------
if [[ "$STYLE_COLOR" = "1" ]]; then
  _STYLE_RESET=$'\033[0m'
  _STYLE_GREEN=$'\033[38;5;71m'   # gentle green
  _STYLE_RED=$'\033[38;5;167m'    # gentle red
  _STYLE_YELLOW=$'\033[38;5;179m' # gentle yellow
  _STYLE_CYAN=$'\033[38;5;73m'    # gentle cyan
  _STYLE_GREY=$'\033[38;5;245m'   # dim grey
  _STYLE_MAGENTA=$'\033[38;5;176m'
  _STYLE_BOLD=$'\033[1m'
else
  _STYLE_RESET=''
  _STYLE_GREEN=''
  _STYLE_RED=''
  _STYLE_YELLOW=''
  _STYLE_CYAN=''
  _STYLE_GREY=''
  _STYLE_MAGENTA=''
  _STYLE_BOLD=''
fi
readonly _STYLE_RESET _STYLE_GREEN _STYLE_RED _STYLE_YELLOW \
         _STYLE_CYAN _STYLE_GREY _STYLE_MAGENTA _STYLE_BOLD

# ---------------------------------------------------------------------------
# Internal glyph set
# ---------------------------------------------------------------------------
if [[ "$STYLE_UNICODE" = "1" ]]; then
  _STYLE_GLYPH_OK='✓'
  _STYLE_GLYPH_FAIL='✗'
  _STYLE_GLYPH_STEP='⏵'
  _STYLE_GLYPH_INFO='●'
  _STYLE_GLYPH_WARN='●'
  _STYLE_GLYPH_DIM='…'
  _STYLE_GLYPH_RETRY='↻'
  _STYLE_GLYPH_JOIN='↦'
else
  _STYLE_GLYPH_OK='[ok]'
  _STYLE_GLYPH_FAIL='[fail]'
  _STYLE_GLYPH_STEP='-->'
  _STYLE_GLYPH_INFO='*'
  _STYLE_GLYPH_WARN='[warn]'
  _STYLE_GLYPH_DIM='...'
  _STYLE_GLYPH_RETRY='[retry]'
  _STYLE_GLYPH_JOIN='->>'
fi
readonly _STYLE_GLYPH_OK _STYLE_GLYPH_FAIL _STYLE_GLYPH_STEP \
         _STYLE_GLYPH_INFO _STYLE_GLYPH_WARN _STYLE_GLYPH_DIM \
         _STYLE_GLYPH_RETRY _STYLE_GLYPH_JOIN

# ---------------------------------------------------------------------------
# Emitters
# ---------------------------------------------------------------------------

# style::ok <msg> — print success line.
style::ok() {
  printf '%s%s%s %s\n' "$_STYLE_GREEN" "$_STYLE_GLYPH_OK" "$_STYLE_RESET" "$*"
  return 0
}

# style::fail <msg> — print failure line. Does NOT exit; preserves $?.
style::fail() {
  printf '%s%s%s %s\n' "$_STYLE_RED" "$_STYLE_GLYPH_FAIL" "$_STYLE_RESET" "$*"
  return 0
}

# style::warn <msg> — print warning line.
style::warn() {
  printf '%s%s%s %s\n' "$_STYLE_YELLOW" "$_STYLE_GLYPH_WARN" "$_STYLE_RESET" "$*"
  return 0
}

# style::info <msg> — print informational line.
style::info() {
  printf '%s%s%s %s\n' "$_STYLE_CYAN" "$_STYLE_GLYPH_INFO" "$_STYLE_RESET" "$*"
  return 0
}

# style::step <msg> — print a step/progress line.
style::step() {
  printf '%s%s%s %s\n' "$_STYLE_CYAN" "$_STYLE_GLYPH_STEP" "$_STYLE_RESET" "$*"
  return 0
}

# style::dim <msg> — print a de-emphasized line.
style::dim() {
  printf '%s%s%s\n' "$_STYLE_GREY" "$*" "$_STYLE_RESET"
  return 0
}

# style::retry <msg> — print a retry line (operation being retried after failure).
style::retry() {
  printf '%s%s%s %s\n' "$_STYLE_YELLOW" "$_STYLE_GLYPH_RETRY" "$_STYLE_RESET" "$*"
  return 0
}

# style::join <msg> — print a fan-in / aggregation result line.
style::join() {
  printf '%s%s%s %s\n' "$_STYLE_CYAN" "$_STYLE_GLYPH_JOIN" "$_STYLE_RESET" "$*"
  return 0
}

# style::header <title> — print a section header. Routes through `gum style`
# when STYLE_USE_GUM=1, otherwise prints a bold/colored plain banner.
style::header() {
  local title="$*"
  if [[ "$STYLE_USE_GUM" = "1" ]]; then
    gum style --foreground 212 --border rounded --padding "0 1" -- "$title" \
      || printf '%s%s== %s ==%s\n' "$_STYLE_BOLD" "$_STYLE_MAGENTA" "$title" "$_STYLE_RESET"
    return 0
  fi
  printf '%s%s== %s ==%s\n' "$_STYLE_BOLD" "$_STYLE_MAGENTA" "$title" "$_STYLE_RESET"
  return 0
}

# style::box <msg> — print a boxed message. Routes through `gum style`
# when STYLE_USE_GUM=1, otherwise prints a simple ASCII frame.
style::box() {
  local msg="$*"
  if [[ "$STYLE_USE_GUM" = "1" ]]; then
    gum style --border normal --padding "1 2" -- "$msg" \
      || _style::ascii_box "$msg"
    return 0
  fi
  _style::ascii_box "$msg"
  return 0
}

_style::ascii_box() {
  local msg="$1"
  local len=${#msg}
  local bar
  bar=$(printf '%*s' $((len + 2)) '' | tr ' ' '-')
  printf '+%s+\n| %s |\n+%s+\n' "$bar" "$msg" "$bar"
  return 0
}

# style::rule — print a horizontal rule sized to terminal width (max 80).
style::rule() {
  local cols=80
  if [[ -n "${COLUMNS:-}" ]]; then
    cols="$COLUMNS"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  elif command -v tput >/dev/null 2>&1; then
    cols="$(tput cols 2>/dev/null || printf '80')"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  fi
  [[ "$cols" -gt 80 ]] && cols=80
  local glyph='-'
  [[ "$STYLE_UNICODE" = "1" ]] && glyph='─'
  local bar
  bar="$(printf '%*s' "$cols" '' | tr ' ' "$glyph")"
  printf '%s%s%s\n' "$_STYLE_GREY" "$bar" "$_STYLE_RESET"
  return 0
}

# style::strip_ansi — filter stdin, removing CSI/SGR escape sequences.
# Useful when redirecting styled output to docs/* files.
style::strip_ansi() {
  sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
  return 0
}
