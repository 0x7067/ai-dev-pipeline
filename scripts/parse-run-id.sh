#!/usr/bin/env bash
# parse-run-id.sh — boundary parser for RUN_ID.
#
# Layer: BOUNDARY. The single ingress point that converts an untrusted
# string (env var, CLI arg, CI translation result, file content) into a
# validated RunId domain value. Per
# .claude/rules/boundary-parse-dont-validate.md, every consumer that
# accepts a run-id from an external source MUST route it through this
# parser before constructing a path or writing a file.
#
# Contract:
#   Input  : a single argument (the candidate run-id) OR, if no arg given,
#            the value of the RUN_ID environment variable.
#   Accept : matches ^[0-9]{8}T[0-9]{6}Z?-[a-f0-9]{6}(-[a-f0-9]{2})?$
#            length 22..26, allowlist [0-9 a-f T Z -].
#            (length bounds derived from the regex itself: 22 is min
#             without Z and without disambiguator; 26 is max with both.)
#   Reject : empty, '..', '/', '\', NUL, whitespace, or any char outside
#            the allowlist.
#   Egress : on accept, prints the canonical id to stdout and exits 0.
#            on reject, prints a single-line structured error to stderr
#            and exits 2.
#
# This script is also intended to be `source`d so other scripts can reuse
# the regex constant. When sourced, it defines RUN_ID_REGEX and the
# parse_run_id function but does not exit on its own.

# Canonical regex. Kept as a single constant so consumers source-and-reuse.
# Length is bounded by the regex itself: min 22 (no Z, no disambiguator),
# max 26 (with both Z and -hh disambiguator).
RUN_ID_REGEX='^[0-9]{8}T[0-9]{6}Z?-[a-f0-9]{6}(-[a-f0-9]{2})?$'

# parse_run_id <candidate>
#   Returns 0 and echoes <candidate> on accept; returns 2 with stderr
#   error on reject. Never mutates filesystem.
parse_run_id() {
  local candidate="${1-}"

  if [ -z "$candidate" ]; then
    printf 'parse-run-id: ERROR: empty run-id\n' >&2
    return 2
  fi

  # Length guard before regex (defence in depth).
  # Bounds are exhaustive over the regex shape:
  #   min = 8 + 1 + 6 + 1 + 6                    = 22  (no Z, no -hh)
  #   max = 8 + 1 + 6 + 1 + 1 + 6 + 1 + 2        = 26  (with Z and -hh)
  local len=${#candidate}
  if [ "$len" -lt 22 ] || [ "$len" -gt 26 ]; then
    printf 'parse-run-id: ERROR: length %d out of range [22..26]: %q\n' "$len" "$candidate" >&2
    return 2
  fi

  # Bash =~ is sufficient; the regex itself denies '/', '\', '.', NUL,
  # whitespace, and every char outside the allowlist.
  if [[ "$candidate" =~ $RUN_ID_REGEX ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  printf 'parse-run-id: ERROR: rejected (regex mismatch): %q\n' "$candidate" >&2
  return 2
}

# When executed directly (not sourced), parse the first arg or RUN_ID env.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  set -uo pipefail
  if [ "$#" -ge 1 ]; then
    parse_run_id "$1"
    exit $?
  fi
  parse_run_id "${RUN_ID-}"
  exit $?
fi
