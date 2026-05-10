#!/usr/bin/env bash
# append-phase-timing.sh — atomic per-phase appender for phase_timings.json.
#
# Layer: SHELL. Mirrors the tempfile + rename pattern used by other run-state
# writers (mint-run-id.sh, queue-pending-approval.sh). One invocation per
# phase; the orchestrator is sequential at the phase boundary so there is
# exactly one writer at a time.
#
# Usage:
#   scripts/append-phase-timing.sh \
#     --run-dir <dir> --name <phase> \
#     --status <ok|fail> --seconds <int> --started-at <ISO8601Z>
#
# Exit:
#   0  appended (or initialized).
#   2  bad arguments.
#   1  filesystem write failure.

set -uo pipefail

usage() {
  cat <<'EOF'
append-phase-timing.sh — append one phase record to ${RUN_DIR}/phase_timings.json.

Required flags:
  --run-dir <dir>          run directory (created if missing)
  --name <phase>           phase name (e.g. plan, implement, verify)
  --status <ok|fail>       phase outcome
  --seconds <int>          elapsed seconds (>= 0)
  --started-at <ISO8601Z>  start timestamp, e.g. 2026-05-09T01:02:03Z

Behavior:
  - Creates ${RUN_DIR}/phase_timings.json with schema_version=1 if missing.
  - Atomically appends the new record (tempfile + mv).
  - Updates total_seconds = sum(phases[*].seconds).
EOF
}

main() {
  local run_dir="" name="" status="" seconds="" started_at=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) usage; return 0 ;;
      --run-dir)    run_dir="${2-}"; shift 2 ;;
      --name)       name="${2-}"; shift 2 ;;
      --status)     status="${2-}"; shift 2 ;;
      --seconds)    seconds="${2-}"; shift 2 ;;
      --started-at) started_at="${2-}"; shift 2 ;;
      *)
        printf 'append-phase-timing: ERROR: unknown arg %q\n' "$1" >&2
        return 2 ;;
    esac
  done

  if [ -z "$run_dir" ] || [ -z "$name" ] || [ -z "$status" ] \
     || [ -z "$seconds" ] || [ -z "$started_at" ]; then
    printf 'append-phase-timing: ERROR: all of --run-dir --name --status --seconds --started-at are required\n' >&2
    return 2
  fi

  case "$status" in ok|fail) ;; *)
    printf 'append-phase-timing: ERROR: --status must be ok|fail (got %q)\n' "$status" >&2
    return 2 ;;
  esac
  if ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
    printf 'append-phase-timing: ERROR: --seconds must be a non-negative integer (got %q)\n' "$seconds" >&2
    return 2
  fi
  if ! [[ "$started_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    printf 'append-phase-timing: ERROR: --started-at must be ISO8601Z (got %q)\n' "$started_at" >&2
    return 2
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf 'append-phase-timing: ERROR: jq is required\n' >&2
    return 2
  fi

  mkdir -p "$run_dir" || return 1
  local out="$run_dir/phase_timings.json"
  local suffix="$$.${RANDOM:-0}"
  local tmp="${out}.tmp.${suffix}"

  local current
  if [ -s "$out" ] && jq empty "$out" >/dev/null 2>&1; then
    current="$(cat "$out")"
  else
    current='{"schema_version":1,"phases":[],"total_seconds":0}'
  fi

  printf '%s' "$current" | jq \
    --arg name "$name" \
    --arg status "$status" \
    --argjson seconds "$seconds" \
    --arg started_at "$started_at" \
    '.schema_version = 1
     | .phases = ((.phases // []) + [{name:$name, status:$status, seconds:$seconds, started_at:$started_at}])
     | .total_seconds = ([.phases[].seconds] | add // 0)' \
    > "$tmp" || { rm -f "$tmp"; return 1; }

  mv "$tmp" "$out" || { rm -f "$tmp"; return 1; }
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
