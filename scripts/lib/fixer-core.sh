#!/usr/bin/env bash
# fixer-core.sh — pure-core helpers for the implementer dispatch overhaul.
#
# Layer: CORE (pure). Per .claude/rules/architecture-fcis.md this file:
#   - performs NO filesystem I/O,
#   - reads NO clock or ambient state,
#   - shells out to NO external tools at runtime (jq, git, etc.),
#   - accepts all required data as explicit function arguments.
#
# Public functions:
#   fixer_partition_queue <findings_json>
#     Reads a JSON array string of findings; emits three tab-separated
#     sections to stdout: safe_auto, gated_auto, manual (one JSON object
#     per line within each section). Requires jq on PATH (no external I/O
#     beyond the jq call on the already-loaded string).
#
#   fixer_precheck_finding <window_text> <token>
#     Pure substring check. Returns "ok" if token appears anywhere in
#     window_text, "stale" otherwise.  The caller (shell) is responsible
#     for reading the ±5-line window from the file and passing it here.
#
#   fixer_gate_pass <applied_count> <failed_count> <error_flag>
#     Returns "run" iff applied_count >= 1 AND error_flag == 0.
#     failed_count is informational only (per OD-1 resolved decision).
#
# Idempotent source guard: _FIXER_CORE_SH_LOADED.
# This file is intended to be `source`d. It defines functions only.

[ "${_FIXER_CORE_SH_LOADED:-}" = "1" ] && return 0
readonly _FIXER_CORE_SH_LOADED=1

# ---------------------------------------------------------------------------
# fixer_partition_queue <findings_json>
#
# Partitions a JSON array of finding objects by their `autofix_class` field
# into three named groups. Emits to stdout:
#
#   safe_auto
#   <json_object>
#   ...
#   gated_auto
#   <json_object>
#   ...
#   manual
#   <json_object>
#   ...
#
# Finding objects that have no `autofix_class` field or an unrecognised value
# are placed in the "manual" group.
#
# Invariant: every input finding appears in exactly one output group.
# Precondition: findings_json is a valid JSON array (caller's responsibility).
# ---------------------------------------------------------------------------
fixer_partition_queue() {
  local findings_json="${1-}"

  if [ -z "$findings_json" ]; then
    printf 'fixer-core: ERROR: fixer_partition_queue: empty findings_json\n' >&2
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf 'fixer-core: ERROR: fixer_partition_queue requires jq on PATH\n' >&2
    return 1
  fi

  # Emit the three labeled sections. jq does the partitioning; bash is the
  # envelope. No filesystem I/O — jq operates on the string passed in via
  # --argjson.
  local safe gated manual
  safe="$(printf '%s' "$findings_json" | \
    jq -c '[.[] | select((.autofix_class // "manual") == "safe_auto")][]')" || {
    printf 'fixer-core: ERROR: fixer_partition_queue: jq parse failed\n' >&2
    return 1
  }
  gated="$(printf '%s' "$findings_json" | \
    jq -c '[.[] | select((.autofix_class // "manual") == "gated_auto")][]')"
  manual="$(printf '%s' "$findings_json" | \
    jq -c '[.[] | select(
      (.autofix_class // "manual") != "safe_auto" and
      (.autofix_class // "manual") != "gated_auto"
    )][]')"

  printf 'safe_auto\n'
  [ -n "$safe" ] && printf '%s\n' "$safe" || true
  printf 'gated_auto\n'
  [ -n "$gated" ] && printf '%s\n' "$gated" || true
  printf 'manual\n'
  [ -n "$manual" ] && printf '%s\n' "$manual" || true
  return 0
}

# ---------------------------------------------------------------------------
# fixer_precheck_finding <window_text> <token>
#
# Pure substring test.
#
# Returns (stdout + exit 0):
#   "ok"    — token is a verbatim substring of window_text
#   "stale" — token is NOT found in window_text
#
# Preconditions (caller's responsibility):
#   window_text  : the ±5-line text block read by the shell wrapper
#   token        : non-empty string from evidence[] of the finding
#
# This function performs NO file I/O. The shell wrapper must read
# the window (lines line-5 through line+5) from the target file and
# pass it as a single string argument.
# ---------------------------------------------------------------------------
fixer_precheck_finding() {
  local window_text="${1-}" token="${2-}"

  if [ -z "$token" ]; then
    printf 'fixer-core: ERROR: fixer_precheck_finding: empty token\n' >&2
    return 1
  fi

  # Pure bash substring check — no regex, no external tools.
  if [[ "$window_text" == *"$token"* ]]; then
    printf 'ok\n'
  else
    printf 'stale\n'
  fi
}

# ---------------------------------------------------------------------------
# fixer_gate_pass <applied_count> <failed_count> <error_flag>
#
# Gating predicate for sequential pass dispatch (OD-1 resolved decision).
#
# Returns (stdout + exit 0):
#   "run"  — next pass should proceed
#   "skip" — next pass should be skipped
#
# Policy (OD-1):
#   run  iff applied_count >= 1 AND error_flag == 0
#   skip otherwise
#   failed_count is informational only; does NOT affect the gate decision.
#
# Preconditions:
#   applied_count : non-negative integer
#   failed_count  : non-negative integer (logged but not used in decision)
#   error_flag    : 0 = no orchestrator error; 1 = unrecoverable error
# ---------------------------------------------------------------------------
fixer_gate_pass() {
  local applied_count="${1-}" failed_count="${2-}" error_flag="${3-}"

  # Validate inputs — refuse to gate on garbage.
  if [[ ! "$applied_count" =~ ^[0-9]+$ ]]; then
    printf 'fixer-core: ERROR: fixer_gate_pass: applied_count not a non-negative integer: %s\n' \
      "$applied_count" >&2
    return 1
  fi
  if [[ ! "$failed_count" =~ ^[0-9]+$ ]]; then
    printf 'fixer-core: ERROR: fixer_gate_pass: failed_count not a non-negative integer: %s\n' \
      "$failed_count" >&2
    return 1
  fi
  if [[ "$error_flag" != "0" && "$error_flag" != "1" ]]; then
    printf 'fixer-core: ERROR: fixer_gate_pass: error_flag must be 0 or 1, got: %s\n' \
      "$error_flag" >&2
    return 1
  fi

  if (( applied_count >= 1 )) && [[ "$error_flag" == "0" ]]; then
    printf 'run\n'
  else
    printf 'skip\n'
  fi
}
