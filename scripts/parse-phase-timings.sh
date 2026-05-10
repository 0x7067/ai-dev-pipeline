#!/usr/bin/env bash
# parse-phase-timings.sh — boundary parser for ${RUN_DIR}/phase_timings.json.
#
# Layer: BOUNDARY. The orchestrator's end-of-run renderer NEVER reads
# phase_timings.json directly; every consumer routes through this parser.
# Per .claude/rules/boundary-parse-dont-validate.md, untrusted JSON on disk
# is parsed into a flat typed key=value form and emitted on stdout.
#
# Schema accepted (v1):
#   {
#     "schema_version": 1,
#     "phases": [
#       { "name": "<phase>", "status": "ok|fail",
#         "seconds": <int>, "started_at": "<ISO8601Z>" },
#       ...
#     ],
#     "total_seconds": <int>
#   }
#
# Output (stdout, on accept), one typed key=value per line:
#   schema_version=1
#   phase_count=<n>
#   phase_1_name=<phase>
#   phase_1_status=ok|fail
#   phase_1_seconds=<int>
#   phase_1_started_at=<ISO8601Z>
#   ... (1-indexed)
#   total_seconds=<int>
#
# Contract:
#   - rc=0 on accept (well-formed JSON + matches schema invariants).
#   - rc=2 on reject (malformed JSON, missing/extra fields, type mismatch).
#   - On reject: clear stderr message naming the file; NO partial stdout.
#   - Fails closed (security-baseline.md). Missing file → rc=2.

set -uo pipefail

usage() {
  cat <<'EOF'
parse-phase-timings.sh — typed reader for phase_timings.json (v1).

Usage:
  parse-phase-timings.sh <path/to/phase_timings.json>

Exit:
  0  parsed; key=value pairs on stdout
  2  malformed input; error on stderr; no stdout
EOF
}

main() {
  if [ "$#" -ne 1 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    [ "$#" -eq 1 ] && return 0
    return 2
  fi
  local path="$1"

  if [ ! -f "$path" ]; then
    printf 'parse-phase-timings: ERROR: file not found: %s\n' "$path" >&2
    return 2
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf 'parse-phase-timings: ERROR: jq is required\n' >&2
    return 2
  fi

  if ! jq empty "$path" >/dev/null 2>&1; then
    printf 'parse-phase-timings: ERROR: %s is not valid JSON\n' "$path" >&2
    return 2
  fi

  # Buffer output; only emit on success (no partial output on reject).
  local buf
  buf="$(jq -r '
    def is_int: type == "number" and (. == (.|floor));
    def is_phase_status: . == "ok" or . == "fail";

    if (.schema_version // null) != 1 then
      "ERR: schema_version must be 1"
    elif (.phases // null) | type != "array" then
      "ERR: phases must be an array"
    elif (.total_seconds // null) | (is_int | not) then
      "ERR: total_seconds must be an integer"
    else
      . as $root
      | (.phases | length) as $n
      | ([range(0; $n) as $i
          | .phases[$i] as $p
          | if ($p | type) != "object" then "ERR: phases[\($i)] not object"
            elif ($p.name // null) | type != "string" then "ERR: phases[\($i)].name missing"
            elif ($p.status // null) | (is_phase_status | not) then "ERR: phases[\($i)].status invalid"
            elif ($p.seconds // null) | (is_int | not) then "ERR: phases[\($i)].seconds invalid"
            elif ($p.started_at // null) | type != "string" then "ERR: phases[\($i)].started_at missing"
            else empty
            end
         ] | first) as $err
      | if $err then $err
        else
          [ "schema_version=1",
            "phase_count=\($n)" ]
          + [ range(0; $n) as $i
              | .phases[$i] as $p
              | "phase_\($i + 1)_name=\($p.name)",
                "phase_\($i + 1)_status=\($p.status)",
                "phase_\($i + 1)_seconds=\($p.seconds)",
                "phase_\($i + 1)_started_at=\($p.started_at)" ]
          + [ "total_seconds=\(.total_seconds)" ]
          | join("\n")
        end
    end
  ' "$path" 2>&1)"
  local rc=$?

  if [ "$rc" -ne 0 ]; then
    printf 'parse-phase-timings: ERROR: jq failed on %s\n' "$path" >&2
    return 2
  fi

  if printf '%s' "$buf" | head -n1 | grep -q '^ERR:'; then
    local msg
    msg="$(printf '%s' "$buf" | head -n1 | sed 's/^ERR: //')"
    printf 'parse-phase-timings: ERROR: %s in %s\n' "$msg" "$path" >&2
    return 2
  fi

  printf '%s\n' "$buf"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
