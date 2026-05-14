#!/usr/bin/env bash
# parse-fixer-pass.sh — boundary parser for fixer-pass-<class>.json sidecars.
#
# Layer: BOUNDARY. Converts the raw JSON sidecar produced by the implementer
# into typed key=value lines consumable by the orchestrator shell. Per
# .claude/rules/boundary-parse-dont-validate.md, no orchestrator code may
# read the sidecar directly — all consumers route through this parser.
#
# Usage:
#   parse-fixer-pass.sh <path>
#   parse-fixer-pass.sh --check <path>   (exit 0 = valid, 1 = schema error)
#
# The <path> argument must point to a completed sidecar file.
# Paths ending in ".tmp" are refused (atomicity guard — see plan invariant 5).
#
# Output (stdout, on accept): one typed key=value per line, for example:
#   class=safe_auto
#   applied_count=3
#   failed_count=1
#   advisory_count=0
#   applied[0].finding_num=1
#   applied[0].file_line=src/foo.sh:42
#   applied[0].title=Use quoted variable
#   failed[0].finding_num=2
#   failed[0].file_line=src/bar.sh:10
#   failed[0].title=Remove unused import
#   failed[0].reason=verify_cmd exited 1
#   advisory[0].finding_num=5
#   advisory[0].file_line=src/baz.sh:7
#   advisory[0].title=Consider using local
#
# Exit codes:
#   0 — sidecar parsed and valid; typed pairs emitted to stdout
#   1 — schema violation (missing key, bad class, missing reason on failed,
#        unknown top-level field, .tmp path)
#   2 — file not found (sidecar absent — distinct signal for orchestrator)
#
# Schema (docs/schemas/fixer-pass-v1.schema.json):
#   Top-level required: class (enum), applied (array), failed (array)
#   Top-level optional: advisory (array)
#   No other top-level fields permitted.
#   Entry required: finding_num (int >=1), file_line (string "path:NN"),
#                   title (string)
#   Entry optional: reason (string; REQUIRED when entry is in failed[])
#
# Style: uses scripts/lib/style.sh emitters for stderr banners.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=lib/style.sh
source "${SCRIPT_DIR}/lib/style.sh"

_PROG="parse-fixer-pass"
_VALID_CLASSES="safe_auto gated_auto manual"
_VALID_TOP_KEYS="class applied failed advisory"

_die() {
  local code="$1"; shift
  style::fail "${_PROG}: ERROR: $*" >&2
  exit "$code"
}

_warn() {
  style::warn "${_PROG}: WARN: $*" >&2
}

# ---------------------------------------------------------------------------
# _check_mode: controls whether output is emitted (false = --check, true = parse)
# ---------------------------------------------------------------------------
_EMIT=1
if [ "${1-}" = "--check" ]; then
  _EMIT=0
  shift
fi

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
_path="${1-}"
if [ -z "$_path" ]; then
  _die 1 "missing path argument. Usage: ${_PROG} [--check] <sidecar.json>"
fi

# Refuse .tmp paths (atomicity invariant).
if [[ "$_path" == *.tmp ]]; then
  _die 1 "refusing to read .tmp-suffixed path (atomicity guard): ${_path}"
fi

# File-not-found → exit 2 (distinct from schema error).
if [ ! -f "$_path" ]; then
  style::fail "${_PROG}: ERROR: sidecar not found: ${_path}" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Parse with jq when available; bash+grep fallback for key detection.
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  # -------------------------------------------------------------------------
  # jq path: full validation + typed output
  # -------------------------------------------------------------------------

  # 1. Check for unknown top-level keys.
  unknown_keys="$(jq -r 'keys[] | select(. != "class" and . != "applied" and . != "failed" and . != "advisory")' \
    "$_path" 2>/dev/null)" || _die 1 "jq failed to parse sidecar: ${_path}"

  if [ -n "$unknown_keys" ]; then
    _die 1 "unknown top-level field(s) in sidecar: $(printf '%s' "$unknown_keys" | tr '\n' ' ')"
  fi

  # 2. Validate required top-level keys exist.
  for _key in class applied failed; do
    has_key="$(jq -r --arg k "$_key" 'has($k) | tostring' "$_path" 2>/dev/null)"
    [ "$has_key" = "true" ] || _die 1 "missing required top-level key: ${_key}"
  done

  # 3. Validate class value.
  _class="$(jq -r '.class' "$_path")"
  _class_valid=0
  for _c in $_VALID_CLASSES; do
    [ "$_c" = "$_class" ] && _class_valid=1 && break
  done
  [ "$_class_valid" -eq 1 ] || _die 1 "invalid class value: '${_class}' (expected one of: ${_VALID_CLASSES})"

  # 4. Validate entry shapes in applied[], failed[], advisory[].
  _validate_entries() {
    local section="$1"
    local require_reason="${2:-0}"
    local count idx finding_num file_line title reason

    count="$(jq -r --arg s "$section" '.[$s] | length' "$_path")"
    idx=0
    while [ "$idx" -lt "$count" ]; do
      finding_num="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].finding_num // empty' "$_path")"
      [ -n "$finding_num" ] || _die 1 "${section}[${idx}]: missing required field 'finding_num'"
      [[ "$finding_num" =~ ^[1-9][0-9]*$ ]] || _die 1 "${section}[${idx}]: finding_num must be integer >= 1, got: ${finding_num}"

      file_line="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].file_line // empty' "$_path")"
      [ -n "$file_line" ] || _die 1 "${section}[${idx}]: missing required field 'file_line'"
      [[ "$file_line" =~ ^.+:[0-9]+$ ]] || _die 1 "${section}[${idx}]: file_line must match 'path:N', got: ${file_line}"

      title="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].title // empty' "$_path")"
      [ -n "$title" ] || _die 1 "${section}[${idx}]: missing required field 'title'"

      if [ "$require_reason" -eq 1 ]; then
        reason="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].reason // empty' "$_path")"
        [ -n "$reason" ] || _die 1 "${section}[${idx}]: missing required field 'reason' (required for failed entries)"
      fi
      idx=$(( idx + 1 ))
    done
    return 0
  }

  _validate_entries "applied"   0
  _validate_entries "failed"    1
  _validate_entries "advisory"  0

  # 5. Emit typed key=value pairs if not in --check mode.
  if [ "$_EMIT" -eq 1 ]; then
    printf 'class=%s\n' "$_class"

    _applied_count="$(jq -r '.applied | length' "$_path")"
    _failed_count="$(jq -r '.failed | length' "$_path")"
    _advisory_count="$(jq -r '.advisory | length' "$_path")"
    printf 'applied_count=%s\n' "$_applied_count"
    printf 'failed_count=%s\n' "$_failed_count"
    printf 'advisory_count=%s\n' "$_advisory_count"

    _emit_entries() {
      local section="$1"
      local count idx
      count="$(jq -r --arg s "$section" '.[$s] | length' "$_path")"
      local idx=0
      while [ "$idx" -lt "$count" ]; do
        local fn fl ti re
        fn="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].finding_num' "$_path")"
        fl="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].file_line' "$_path")"
        ti="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].title' "$_path")"
        printf '%s[%s].finding_num=%s\n' "$section" "$idx" "$fn"
        printf '%s[%s].file_line=%s\n'   "$section" "$idx" "$fl"
        printf '%s[%s].title=%s\n'       "$section" "$idx" "$ti"
        re="$(jq -r --arg s "$section" --argjson i "$idx" '.[$s][$i].reason // empty' "$_path")"
        [ -n "$re" ] && printf '%s[%s].reason=%s\n' "$section" "$idx" "$re" || true
        idx=$(( idx + 1 ))
      done
      return 0
    }

    _emit_entries "applied"
    _emit_entries "failed"
    _emit_entries "advisory"
  fi

else
  # -------------------------------------------------------------------------
  # Bash+grep fallback — best-effort; fail-closed on ambiguity.
  # -------------------------------------------------------------------------
  _warn "jq not found; using bash+grep fallback (reduced validation)"

  # Refuse if any unknown top-level key is detected.
  # Strategy: grep for "key": at start of a line (top-level keys in compact JSON
  # are hard to detect without jq; fail-closed if the structure looks non-trivial).
  if grep -qP '^[[:space:]]*"(?!class|applied|failed|advisory)([^"]+)"[[:space:]]*:' "$_path" 2>/dev/null; then
    _die 1 "unknown top-level field detected (bash fallback — fail-closed)"
  fi

  # Check required keys are present.
  for _key in class applied failed; do
    grep -q "\"${_key}\"" "$_path" || _die 1 "missing required top-level key: ${_key}"
  done

  # Extract and validate class (simple grep).
  _class="$(grep -o '"class"[[:space:]]*:[[:space:]]*"[^"]*"' "$_path" | \
    sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)"
  if [ -z "$_class" ]; then
    _die 1 "could not extract class value"
  fi
  _class_valid=0
  for _c in $_VALID_CLASSES; do
    [ "$_c" = "$_class" ] && _class_valid=1 && break
  done
  [ "$_class_valid" -eq 1 ] || _die 1 "invalid class value: '${_class}'"

  # In fallback mode we cannot safely emit structured output — jq is required
  # for full typed emission. Emit partial header only.
  if [ "$_EMIT" -eq 1 ]; then
    printf 'class=%s\n' "$_class"
    _warn "jq absent: applied/failed entry pairs not emitted; orchestrator must install jq"
  fi
fi

style::ok "${_PROG}: sidecar valid: ${_path}" >&2
exit 0
