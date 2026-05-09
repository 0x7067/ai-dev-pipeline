#!/usr/bin/env bash
# parse-pending-approval.sh — boundary parser for ${RUN_DIR}/.pending-approval.json.
#
# Layer: BOUNDARY. Per .claude/rules/boundary-parse-dont-validate.md, the
# pending-approval marker is untrusted bytes on disk; a resuming /ship
# orchestrator routes it through this parser before branching.
#
# Schema (one JSON object on a single line, written by
# scripts/queue-pending-approval.sh atomically via tempfile + rename):
#   {
#     "run_id":"<RunId>",
#     "gate":"<plan|release|refactor-plan>",
#     "deadline_iso":"<iso8601 or empty>",
#     "plan_hash":"<hex or empty>",
#     "created_at":"<iso8601-utc>"
#   }
#
# On accept, prints typed key=value pairs (one per line). On reject,
# exits 2 with a single-line diagnostic (fail-closed per
# security-baseline.md).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=lib/decisions-core.sh
source "${SCRIPT_DIR}/lib/decisions-core.sh"
# shellcheck source=parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

# parse_pending_approval <path>
parse_pending_approval() {
  local path="${1-}"
  if [ -z "$path" ]; then
    printf 'parse-pending-approval: ERROR: missing path\n' >&2
    return 2
  fi
  if [ ! -f "$path" ]; then
    printf 'parse-pending-approval: ERROR: file not found: %s\n' "$path" >&2
    return 2
  fi
  local line
  line="$(head -n1 "$path")"
  # ANSI hard reject.
  case "$line" in
    *$'\x1b'*)
      printf 'parse-pending-approval: ERROR: ANSI escape in marker\n' >&2
      return 2
      ;;
  esac

  # Reuse decision_record_parse-style decoding by adapting the shape: the
  # marker uses the same flat JSON object encoding (no nested objects),
  # so we can reuse the encoder/decoder discipline. We parse manually
  # here because field set differs.
  case "$line" in
    \{*\}) : ;;
    *)
      printf 'parse-pending-approval: ERROR: not a JSON object\n' >&2
      return 2
      ;;
  esac
  local body="${line#\{}"; body="${body%\}}"

  # Anchored, key-ordered parsing — mirrors the canonical writer in
  # scripts/queue-pending-approval.sh. Avoids the comma-split fragility
  # the reviewer flagged in decisions-core.sh: any field value containing
  # `,` would otherwise truncate. We honor the encoder's two escapes
  # (`\\` and `\"`) and reject any other escape (fail-closed).
  local expected_keys=( run_id gate deadline_iso plan_hash created_at )
  local decoded_values=( "" "" "" "" "" )
  local cursor=0
  local body_len=${#body}
  local i key prefix value ch esc
  for i in "${!expected_keys[@]}"; do
    key="${expected_keys[$i]}"
    prefix="\"${key}\":\""
    if [ "${body:$cursor:${#prefix}}" != "$prefix" ]; then
      printf 'parse-pending-approval: ERROR: expected key %q at offset %d\n' \
        "$key" "$cursor" >&2
      return 2
    fi
    cursor=$((cursor + ${#prefix}))
    value=""
    while [ "$cursor" -lt "$body_len" ]; do
      ch="${body:$cursor:1}"
      if [ "$ch" = "\\" ]; then
        if [ $((cursor + 1)) -ge "$body_len" ]; then
          printf 'parse-pending-approval: ERROR: dangling escape\n' >&2
          return 2
        fi
        esc="${body:$((cursor + 1)):1}"
        case "$esc" in
          \\|\") : ;;
          *)
            printf 'parse-pending-approval: ERROR: unsupported escape \\%s\n' "$esc" >&2
            return 2
            ;;
        esac
        value="${value}${ch}${esc}"
        cursor=$((cursor + 2))
        continue
      fi
      if [ "$ch" = '"' ]; then
        cursor=$((cursor + 1))
        break
      fi
      value="${value}${ch}"
      cursor=$((cursor + 1))
    done
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    decoded_values[$i]="$value"
    if [ "$i" -lt $((${#expected_keys[@]} - 1)) ]; then
      if [ "${body:$cursor:1}" != "," ]; then
        printf 'parse-pending-approval: ERROR: expected , after %q\n' "$key" >&2
        return 2
      fi
      cursor=$((cursor + 1))
    else
      if [ "$cursor" -ne "$body_len" ]; then
        printf 'parse-pending-approval: ERROR: trailing data\n' >&2
        return 2
      fi
    fi
  done
  local run_id="${decoded_values[0]}"
  local gate="${decoded_values[1]}"
  local deadline_iso="${decoded_values[2]}"
  local plan_hash="${decoded_values[3]}"
  local created_at="${decoded_values[4]}"

  # Validate (postcondition assertions per assertions-and-invariants.md).
  if [ -z "$run_id" ] || [ -z "$gate" ] || [ -z "$created_at" ]; then
    printf 'parse-pending-approval: ERROR: missing required field\n' >&2
    return 2
  fi
  parse_run_id "$run_id" >/dev/null || {
    printf 'parse-pending-approval: ERROR: invalid run_id\n' >&2
    return 2
  }
  case "$gate" in
    plan|release|refactor-plan) : ;;
    *)
      printf 'parse-pending-approval: ERROR: invalid gate %q\n' "$gate" >&2
      return 2
      ;;
  esac

  printf 'run_id=%s\n' "$run_id"
  printf 'gate=%s\n' "$gate"
  printf 'deadline_iso=%s\n' "$deadline_iso"
  printf 'plan_hash=%s\n' "$plan_hash"
  printf 'created_at=%s\n' "$created_at"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  parse_pending_approval "${1-}"
  exit $?
fi
