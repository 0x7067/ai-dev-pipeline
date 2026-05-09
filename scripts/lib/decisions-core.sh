#!/usr/bin/env bash
# decisions-core.sh — pure (FC) helpers for the decisions audit log.
#
# Layer: CORE. Per .claude/rules/architecture-fcis.md, this file MUST be
# free of I/O. Functions take explicit parameters (including `now`) and
# return string-encoded domain values via stdout. The shell appender
# (scripts/append-decision.sh) is responsible for writing to disk.
#
# Domain types:
#   DecisionRecord = { ts, actor, gate, verb, rationale, plan_hash }
#     ts        : ISO-8601 UTC timestamp string (caller-supplied — purity)
#     actor     : "user" | "auto" | "time-box"
#     gate      : "plan" | "release" | "refactor-plan"
#     verb      : "approve" | "edit" | "reject"
#     rationale : free-form short string (no newlines, no ANSI)
#     plan_hash : hex digest or empty string
#
# The on-disk encoding is one JSON object per line (JSONL). The CORE
# function emits the JSON; the SHELL appender flushes it.

# Guard against double-source.
if [ -n "${_DECISIONS_CORE_LOADED:-}" ]; then return 0 2>/dev/null || true; fi
_DECISIONS_CORE_LOADED=1

# decision_record_build <ts> <actor> <gate> <verb> <rationale> <plan_hash>
#   Echoes a single-line JSON object on success; returns 2 on bad input.
#   Pure: no filesystem, no clock, no network. Caller injects `ts`.
decision_record_build() {
  local ts="${1-}" actor="${2-}" gate="${3-}" verb="${4-}"
  local rationale="${5-}" plan_hash="${6-}"

  # Preconditions (per .claude/rules/assertions-and-invariants.md):
  #   - ts must be non-empty (caller's responsibility per FC purity)
  #   - actor ∈ allowed set
  #   - gate ∈ allowed set
  #   - verb ∈ allowed set
  #   - rationale + plan_hash MUST NOT contain newlines or ANSI
  case "$ts" in
    "") printf 'decision_record_build: ts required\n' >&2; return 2 ;;
  esac
  case "$actor" in
    user|auto|time-box) : ;;
    *) printf 'decision_record_build: invalid actor %q\n' "$actor" >&2; return 2 ;;
  esac
  case "$gate" in
    plan|release|refactor-plan) : ;;
    *) printf 'decision_record_build: invalid gate %q\n' "$gate" >&2; return 2 ;;
  esac
  case "$verb" in
    approve|edit|reject) : ;;
    *) printf 'decision_record_build: invalid verb %q\n' "$verb" >&2; return 2 ;;
  esac
  for f in "$rationale" "$plan_hash" "$ts"; do
    case "$f" in
      *$'\n'*|*$'\r'*|*$'\x1b'*)
        printf 'decision_record_build: forbidden control char in field\n' >&2
        return 2
        ;;
    esac
  done

  printf '{"ts":%s,"actor":%s,"gate":%s,"verb":%s,"rationale":%s,"plan_hash":%s}\n' \
    "$(_dr_jstr "$ts")" \
    "$(_dr_jstr "$actor")" \
    "$(_dr_jstr "$gate")" \
    "$(_dr_jstr "$verb")" \
    "$(_dr_jstr "$rationale")" \
    "$(_dr_jstr "$plan_hash")"
}

# decision_record_parse <jsonl-line>
#   Parses one JSONL line back into key=value pairs (one per line).
#   Inverse of decision_record_build for the shape above. Pure.
#
#   Implementation: the encoder writes a FIXED key set in a FIXED order, so
#   the parser anchors on those keys instead of splitting on `,` (which
#   would silently truncate any rationale containing a comma — a real bug
#   caught in review). For each expected key we:
#     1. consume `"key":` from the cursor
#     2. read a JSON string token, respecting `\\` and `\"` escapes
#     3. consume the trailing `,` (or assert end-of-body for the last key)
#   Postcondition (assertion per .claude/rules/assertions-and-invariants.md):
#   every required key MUST be present and decoded; any deviation returns
#   non-zero with a single-line diagnostic. No silent empty `=` lines.
decision_record_parse() {
  local line="${1-}"
  if [ -z "$line" ]; then
    printf 'decision_record_parse: empty\n' >&2
    return 2
  fi
  case "$line" in
    \{*\}) : ;;
    *) printf 'decision_record_parse: not a JSON object: %q\n' "$line" >&2; return 2 ;;
  esac
  local body="${line#\{}"; body="${body%\}}"

  # Fixed schema: keys consumed in this exact order, mirroring the encoder.
  # Parallel arrays instead of an associative array so this works under
  # bash 3.2 (the macOS system bash). The two arrays stay aligned by index.
  local expected_keys=( ts actor gate verb rationale plan_hash )
  local decoded_values=( "" "" "" "" "" "" )
  local decoded_set=( 0 0 0 0 0 0 )
  local cursor=0
  local body_len=${#body}
  local i key prefix value ch esc
  for i in "${!expected_keys[@]}"; do
    key="${expected_keys[$i]}"
    prefix="\"${key}\":\""
    # Anchor: at cursor, the next bytes MUST be `"<key>":"`.
    if [ "${body:$cursor:${#prefix}}" != "$prefix" ]; then
      printf 'decision_record_parse: expected key %q at offset %d\n' "$key" "$cursor" >&2
      return 2
    fi
    cursor=$((cursor + ${#prefix}))
    # Read string token byte-by-byte until an UNESCAPED closing quote.
    # `\\` and `\"` are the only escapes _dr_jstr produces; reject others.
    value=""
    while [ "$cursor" -lt "$body_len" ]; do
      ch="${body:$cursor:1}"
      if [ "$ch" = "\\" ]; then
        # Escape sequence: peek the next byte literally.
        if [ $((cursor + 1)) -ge "$body_len" ]; then
          printf 'decision_record_parse: dangling escape at offset %d\n' "$cursor" >&2
          return 2
        fi
        esc="${body:$((cursor + 1)):1}"
        case "$esc" in
          \\|\") : ;;
          *)
            printf 'decision_record_parse: unsupported escape \\%s at offset %d\n' \
              "$esc" "$cursor" >&2
            return 2
            ;;
        esac
        value="${value}${ch}${esc}"
        cursor=$((cursor + 2))
        continue
      fi
      if [ "$ch" = '"' ]; then
        # End of string token.
        cursor=$((cursor + 1))
        break
      fi
      value="${value}${ch}"
      cursor=$((cursor + 1))
    done
    # Decode the two escapes the encoder produces. Order matters: decode
    # \" before \\ so that an encoded \\ does not consume the trailing "
    # of an adjacent escape.
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    decoded_values[$i]="$value"
    decoded_set[$i]=1
    # Between fields: expect `,`; after the last field: expect end-of-body.
    if [ "$i" -lt $((${#expected_keys[@]} - 1)) ]; then
      if [ "${body:$cursor:1}" != "," ]; then
        printf 'decision_record_parse: expected , after %q at offset %d\n' \
          "$key" "$cursor" >&2
        return 2
      fi
      cursor=$((cursor + 1))
    else
      if [ "$cursor" -ne "$body_len" ]; then
        printf 'decision_record_parse: trailing data after last key at offset %d\n' \
          "$cursor" >&2
        return 2
      fi
    fi
  done

  # Postcondition assert: every expected key was decoded.
  for i in "${!expected_keys[@]}"; do
    if [ "${decoded_set[$i]}" != "1" ]; then
      printf 'decision_record_parse: BUG: key %q missing post-parse\n' \
        "${expected_keys[$i]}" >&2
      return 2
    fi
    printf '%s=%s\n' "${expected_keys[$i]}" "${decoded_values[$i]}"
  done
}

# _dr_jstr — minimal JSON string encoder.
# Handles: backslash, double-quote, control chars rejected upstream, so
# the encoder only needs to escape \\ and \".
_dr_jstr() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}
