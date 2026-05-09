#!/usr/bin/env bash
# manifest-core.sh — pure builders for the run manifest (v1).
#
# Layer: CORE (pure). Per .claude/rules/architecture-fcis.md this file:
#   - performs NO filesystem I/O,
#   - reads NO clock,
#   - shells out to NO git/hashing tool,
#   - reads NO ambient state.
# All such inputs are passed in by the shell writer.
#
# Public functions (all emit JSON to stdout):
#   manifest_json_escape <raw>
#   manifest_build_entry <kind> <path> <sha256> <bytes> [<schema>]
#   manifest_build <run_id> <started_at> <ended_at> <command> <mode> \
#                  <risk_tier> <status> <git_head> <git_branch> <git_dirty> \
#                  <entries_json_array>
#
# Determinism contract: identical inputs produce byte-identical output.
# Key order is fixed. No timestamps are read; only the explicit
# started_at/ended_at parameters are emitted.
#
# This file is intended to be `source`d. It defines functions and exits
# nothing on its own.

# manifest_json_escape <raw>
#   JSON-escapes a string per RFC 8259, no surrounding quotes. Handles
#   backslash, double-quote, control bytes < 0x20, and DEL (0x7F).
manifest_json_escape() {
  local s="${1-}"
  # Order matters: backslash first.
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\b'/\\b}
  s=${s//$'\f'/\\f}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  # Remaining low control bytes 0x00-0x1f (minus those handled above).
  # Bash parameter expansion can't easily map these to \uXXXX; iterate.
  local out="" ch code i
  for (( i=0; i<${#s}; i++ )); do
    ch=${s:i:1}
    printf -v code '%d' "'$ch"
    if [ "$code" -lt 32 ]; then
      printf -v esc '\\u%04x' "$code"
      out+="$esc"
    else
      out+="$ch"
    fi
  done
  printf '%s' "$out"
}

# _manifest_kv_string <key> <raw_value>
#   Emits "key":"escaped-value". No leading/trailing whitespace.
_manifest_kv_string() {
  local key="$1" raw="$2" esc
  esc=$(manifest_json_escape "$raw")
  printf '"%s":"%s"' "$key" "$esc"
}

# _manifest_kv_int <key> <int>
_manifest_kv_int() {
  local key="$1" v="$2"
  # Precondition: v is a non-negative integer. Per
  # .claude/rules/assertions-and-invariants.md, when code says
  # "this can never happen" we assert. Crash-loud on violation rather
  # than emit invalid JSON downstream.
  if ! [[ "$v" =~ ^[0-9]+$ ]]; then
    printf 'manifest_core: ASSERTION FAILED: %s expects non-negative int, got: %q\n' "$key" "$v" >&2
    return 1
  fi
  printf '"%s":%s' "$key" "$v"
}

# _manifest_kv_bool <key> <true|false>
_manifest_kv_bool() {
  local key="$1" v="$2"
  case "$v" in
    true|false) ;;
    *) v="false" ;;
  esac
  printf '"%s":%s' "$key" "$v"
}

# manifest_build_entry <kind> <path> <sha256> <bytes> [<schema>]
#   Emits a single artifact entry as a compact JSON object.
manifest_build_entry() {
  local kind="$1" path="$2" sha="$3" bytes="$4" schema="${5-}"
  local out="" kv
  out+="{"
  out+=$(_manifest_kv_string "kind" "$kind")
  out+=","
  out+=$(_manifest_kv_string "path" "$path")
  out+=","
  out+=$(_manifest_kv_string "sha256" "$sha")
  out+=","
  # Propagate _manifest_kv_int's precondition assertion (fail-closed).
  if ! kv=$(_manifest_kv_int "bytes" "$bytes"); then
    return 1
  fi
  out+="$kv"
  if [ -n "$schema" ]; then
    out+=","
    out+=$(_manifest_kv_string "schema" "$schema")
  fi
  out+="}"
  printf '%s' "$out"
}

# manifest_build_entries_array <entry_json> [<entry_json> ...]
#   Joins pre-built entry objects into a JSON array.
manifest_build_entries_array() {
  local out="[" first=1 e
  for e in "$@"; do
    if [ "$first" = "1" ]; then
      first=0
    else
      out+=","
    fi
    out+="$e"
  done
  out+="]"
  printf '%s' "$out"
}

# manifest_build <run_id> <started_at> <ended_at> <command> <mode> \
#                <risk_tier> <status> <git_head> <git_branch> <git_dirty> \
#                <entries_array_json>
#
# All values are passed in by the shell. `git_dirty` is the literal string
# "true" or "false". `entries_array_json` is a pre-built JSON array
# (e.g. "[{...},{...}]" or "[]").
#
# Emits the full manifest JSON object on stdout, no trailing newline.
manifest_build() {
  local run_id="$1" started_at="$2" ended_at="$3" command="$4" mode="$5"
  local risk_tier="$6" status="$7" git_head="$8" git_branch="$9" git_dirty="${10}"
  local entries="${11}"

  local out=""
  out+="{"
  out+=$(_manifest_kv_string "schema" "run-manifest/v1")
  out+=","
  out+=$(_manifest_kv_string "run_id" "$run_id")
  out+=","
  out+=$(_manifest_kv_string "started_at" "$started_at")
  out+=","
  out+=$(_manifest_kv_string "ended_at" "$ended_at")
  out+=","
  out+=$(_manifest_kv_string "command" "$command")
  out+=","
  out+=$(_manifest_kv_string "mode" "$mode")
  out+=","
  out+=$(_manifest_kv_string "risk_tier" "$risk_tier")
  out+=","
  out+=$(_manifest_kv_string "status" "$status")
  out+=","
  # git sub-object
  out+='"git":{'
  out+=$(_manifest_kv_string "head" "$git_head")
  out+=","
  out+=$(_manifest_kv_string "branch" "$git_branch")
  out+=","
  out+=$(_manifest_kv_bool "dirty" "$git_dirty")
  out+="},"
  out+='"artifacts":'
  out+="$entries"
  out+="}"
  printf '%s' "$out"
}
