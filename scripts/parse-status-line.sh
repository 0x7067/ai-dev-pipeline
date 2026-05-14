#!/usr/bin/env bash
# parse-status-line.sh — boundary parser for agent STATUS lines.
#
# Layer: BOUNDARY. Single ingress for converting an untrusted agent STATUS
# stdout line into a typed AgentStatus value. Per
# .claude/rules/boundary-parse-dont-validate.md, every consumer that
# reads a STATUS line MUST route it through this parser before branching
# on its content. This replaces ad-hoc grep/cut at call sites.
#
# Grammar (canonical):
#   STATUS: <status> | <field>=<value> | ... | <free-form summary> | report=<path>
#
# Where <status> is one of: ok | go | no-go | fail | blocked | queued.
# Recognized fields (any order, all optional except status & report):
#   risk=<low|medium|high|unknown>
#   blocking=<int>           # reviewer
#   risk_reason=<phrase>     # planner — added 2026-05; backward-compatible
# Any unrecognized `key=value` pair is preserved as part of the summary.
# Free text after fields and before `report=` is the summary.
#
# Backward compatibility: a missing `risk_reason` field MUST NOT break
# parsing. The parser emits `risk_reason=(unspecified)` when absent.
#
# Contract:
#   Input  : a single argument (the STATUS line text) OR stdin.
#   Accept : line begins with `STATUS:` (after trim) and contains at
#            least one `|` separator and a `report=` field.
#   Reject : malformed → exit 2 with a single-line diagnostic on stderr.
#            Fail-closed per .claude/rules/security-baseline.md — a
#            malformed STATUS line never auto-approves anything.
#   Egress : on accept, prints typed key=value pairs to stdout (one per
#            line):
#              status=<value>
#              risk=<value>           # defaulted to "unknown" if absent
#              risk_reason=<value>    # defaulted to "(unspecified)"
#              blocking=<value>       # defaulted to "" (empty) if absent
#              summary=<value>
#              report=<value>
#
# This script is also intended to be sourced; sourcing exposes
# `parse_status_line` without exiting.

set -uo pipefail

# Allowed status verbs.
_STATUS_LINE_VERBS_RE='^(ok|go|no-go|fail|blocked|queued)$'
# Allowed risk tiers.
_STATUS_LINE_RISK_RE='^(low|medium|high|unknown)$'

# parse_status_line <line>
#   Echoes typed key=value lines on accept; returns 2 on reject with stderr.
parse_status_line() {
  local line="${1-}"

  # Trim leading/trailing whitespace.
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  if [ -z "$line" ]; then
    printf 'parse-status-line: ERROR: empty input\n' >&2
    return 2
  fi

  # Must begin with `STATUS:`.
  case "$line" in
    STATUS:*) : ;;
    *)
      printf 'parse-status-line: ERROR: missing STATUS: prefix: %q\n' "$line" >&2
      return 2
      ;;
  esac

  # Strip the `STATUS:` prefix; keep the remainder.
  local body="${line#STATUS:}"
  # Trim space after colon.
  body="${body# }"

  # Must contain at least one pipe separator.
  case "$body" in
    *\|*) : ;;
    *)
      printf 'parse-status-line: ERROR: no field separator |: %q\n' "$line" >&2
      return 2
      ;;
  esac

  # Split on `|` into tokens, trimming each.
  local IFS='|'
  # shellcheck disable=SC2206
  local tokens=( $body )
  unset IFS

  local status="" risk="unknown" risk_reason="(unspecified)" blocking=""
  local report="" summary_parts=()
  local first=1
  local tok trimmed key value
  for tok in "${tokens[@]}"; do
    trimmed="${tok#"${tok%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -z "$trimmed" ] && continue

    if [ "$first" = "1" ]; then
      status="$trimmed"
      first=0
      continue
    fi

    case "$trimmed" in
      *=*)
        key="${trimmed%%=*}"
        value="${trimmed#*=}"
        case "$key" in
          risk)         risk="$value" ;;
          risk_reason)  risk_reason="$value" ;;
          blocking)     blocking="$value" ;;
          advisory)     : ;;  # advisory count is informational; not used by policy_apply
          report)       report="$value" ;;
          *)            summary_parts+=("$trimmed") ;;
        esac
        ;;
      *)
        summary_parts+=("$trimmed")
        ;;
    esac
  done

  # Validate status verb.
  if ! [[ "$status" =~ $_STATUS_LINE_VERBS_RE ]]; then
    printf 'parse-status-line: ERROR: invalid status verb %q\n' "$status" >&2
    return 2
  fi

  # Validate risk tier (already defaulted).
  if ! [[ "$risk" =~ $_STATUS_LINE_RISK_RE ]]; then
    printf 'parse-status-line: ERROR: invalid risk tier %q\n' "$risk" >&2
    return 2
  fi

  # Require report field.
  if [ -z "$report" ]; then
    printf 'parse-status-line: ERROR: missing report= field\n' >&2
    return 2
  fi

  # Reject ANSI escapes anywhere — output-style.md hard rule.
  case "$line" in
    *$'\x1b'*)
      printf 'parse-status-line: ERROR: ANSI escape in STATUS line\n' >&2
      return 2
      ;;
  esac

  # Reconstruct summary preserving order.
  local summary=""
  if [ "${#summary_parts[@]}" -gt 0 ]; then
    local i
    for i in "${!summary_parts[@]}"; do
      if [ "$i" -eq 0 ]; then
        summary="${summary_parts[$i]}"
      else
        summary="${summary} | ${summary_parts[$i]}"
      fi
    done
  fi

  printf 'status=%s\n' "$status"
  printf 'risk=%s\n' "$risk"
  printf 'risk_reason=%s\n' "$risk_reason"
  printf 'blocking=%s\n' "$blocking"
  printf 'summary=%s\n' "$summary"
  printf 'report=%s\n' "$report"
  return 0
}

# When executed directly, parse arg or stdin.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -ge 1 ]; then
    parse_status_line "$1"
    exit $?
  fi
  # Read first non-empty line from stdin.
  _line=""
  while IFS= read -r _line; do
    [ -n "$_line" ] && break
  done
  parse_status_line "$_line"
  exit $?
fi
