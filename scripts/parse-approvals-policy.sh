#!/usr/bin/env bash
# parse-approvals-policy.sh — boundary parser for .claude/policy/approvals.yaml.
#
# Layer: BOUNDARY. Converts the untrusted YAML file into a flat,
# line-oriented typed key=value form consumable by shell. Per
# .claude/rules/boundary-parse-dont-validate.md, no orchestrator code
# may read the YAML directly — every consumer routes through this parser.
#
# The grammar accepted is the strict subset used by the policy file:
#   - top-level scalars (version: 1)
#   - top-level lists (modes:\n  - auto)
#   - one level of nested mappings (plan_gate.auto.low: skip)
#   - leaf scalars: int | bare word | yes/no/on/off
#   - one nested list under release_gate.verbs / plan_gate_verbs
#
# Anything outside this grammar is rejected with a line-numbered error.
# Fail-closed per .claude/rules/security-baseline.md — a malformed file
# means the orchestrator refuses to run.
#
# Output (stdout, on accept): one typed `path=value` per line, e.g.
#   version=1
#   modes[0]=auto
#   modes[1]=strict
#   plan_gate.auto.low=skip
#   plan_gate.auto.medium=prompt
#   release_gate.auto_approve_when.mode=auto
#   release_gate.verbs[0]=approve
#   release_gate.verbs[1]=reject
#   plan_gate_verbs[0]=approve
#   plan_gate_verbs[1]=edit
#   plan_gate_verbs[2]=reject
#   refactor_scope_threshold.files=10
#   refactor_scope_threshold.loc=300
#   time_box.default=off
#   time_box.min_seconds=60
#   time_box.max_seconds=86400
#   queue_mode.enabled=true
#
# After emission, the parser validates required invariants:
#   I1 version == 1
#   I2 modes contains exactly auto and strict
#   I3 release_gate.verbs MUST NOT contain `edit` (plan invariant 8)
#   I4 plan_gate_verbs subset-of {approve, edit, reject}
#   I5 refactor_scope_threshold.files and .loc are non-negative integers
#   I6 time_box.{min,max}_seconds are positive integers, min <= max
#
# Contract:
#   Input  : path argument to a YAML file.
#   Accept : grammar matches AND all invariants hold → exit 0, emit pairs.
#   Reject : exit 2 with `parse-approvals-policy: ERROR: line N: <msg>`.

set -o pipefail

_PARSE_POLICY_VALID_VERBS_RE='^(approve|edit|reject)$'

_pp_die() {
  local lineno="$1"; shift
  printf 'parse-approvals-policy: ERROR: line %s: %s\n' "$lineno" "$*" >&2
  exit 2
}

# parse_approvals_policy <path>
parse_approvals_policy() {
  local path="${1-}"
  if [ -z "$path" ]; then
    printf 'parse-approvals-policy: ERROR: missing path argument\n' >&2
    return 2
  fi
  if [ ! -f "$path" ]; then
    printf 'parse-approvals-policy: ERROR: file not found: %s\n' "$path" >&2
    return 2
  fi

  local lineno=0
  # Stack of currently open mappings: key1.key2…
  local stack=()
  # Indent (column count) at each stack depth (parallel to stack[]).
  local indents=()
  # Most recent list key (for `key:` followed by `- item` lines) and its base indent.
  local list_key=""
  local list_indent=-1
  local list_idx=0
  local line raw indent stripped

  # Accumulator for output (so invariant checks can run before printing).
  local -a out=()

  # Helper: pop frames whose indent >= current indent.
  _pp_pop_to() {
    local target_indent="$1"
    while [ "${#stack[@]}" -gt 0 ]; do
      local last_idx=$((${#indents[@]} - 1))
      local last_indent="${indents[$last_idx]}"
      if [ "$last_indent" -ge "$target_indent" ]; then
        unset 'stack[last_idx]'
        unset 'indents[last_idx]'
        stack=("${stack[@]}")
        indents=("${indents[@]}")
      else
        break
      fi
    done
  }

  _pp_path() {
    local key="$1"
    if [ "${#stack[@]}" -eq 0 ]; then
      printf '%s' "$key"
    else
      local IFS=.
      printf '%s.%s' "${stack[*]}" "$key"
    fi
  }

  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    # Strip comments (# not in quotes — values here have no quotes).
    line="${raw%%#*}"
    # Trim trailing whitespace.
    line="${line%"${line##*[![:space:]]}"}"
    # Skip blank lines.
    if [ -z "${line//[[:space:]]/}" ]; then
      continue
    fi

    # Compute indent (count leading spaces; tabs are forbidden).
    case "$line" in
      *$'\t'*)
        _pp_die "$lineno" "tabs not allowed in YAML indent"
        ;;
    esac
    stripped="${line#"${line%%[![:space:]]*}"}"
    indent=$(( ${#line} - ${#stripped} ))

    if [[ "$stripped" =~ ^- ]]; then
      # List item.
      if [ "$list_indent" -lt 0 ] || [ "$indent" -le "$list_indent" ]; then
        _pp_die "$lineno" "unexpected list item (no open list)"
      fi
      local item="${stripped#- }"
      item="${item# }"
      # Reject quoted strings to keep grammar simple.
      case "$item" in
        \"*|\'*) _pp_die "$lineno" "quoted list item not supported: $item" ;;
        *:*)     _pp_die "$lineno" "mapping in list not supported: $item" ;;
      esac
      out+=("${list_key}[${list_idx}]=${item}")
      list_idx=$((list_idx + 1))
      continue
    fi

    # End any pending list when indent regresses.
    if [ "$list_indent" -ge 0 ] && [ "$indent" -le "$list_indent" ]; then
      list_key=""
      list_indent=-1
      list_idx=0
    fi

    # key: value | key:
    if [[ ! "$stripped" =~ ^[a-zA-Z_][a-zA-Z0-9_]*: ]]; then
      _pp_die "$lineno" "expected key: prefix, got: $stripped"
    fi
    local key="${stripped%%:*}"
    local rest="${stripped#*:}"
    rest="${rest# }"

    # Adjust stack to current indent.
    _pp_pop_to "$indent"

    if [ -z "$rest" ]; then
      # Open a new mapping or list — we don't know yet, decide on next line.
      stack+=("$key")
      indents+=("$indent")
      # Tentatively treat as list — list detection is keyed on next `- ` line.
      list_key="$(_pp_path "")"
      list_key="${list_key%.}"
      list_indent="$indent"
      list_idx=0
    else
      # Scalar.
      local full
      full="$(_pp_path "$key")"
      # Reject quoted/multiline scalars.
      case "$rest" in
        \"*|\'*|\>*|\|*) _pp_die "$lineno" "quoted/multiline scalar not supported: $rest" ;;
      esac
      out+=("${full}=${rest}")
    fi
  done < "$path"

  # ---- Invariant checks ----
  local kv version="" has_auto=0 has_strict=0
  local edit_in_release=0
  local files_thr="" loc_thr=""
  local tb_min="" tb_max=""
  for kv in "${out[@]}"; do
    case "$kv" in
      version=*)
        version="${kv#version=}"
        ;;
      modes\[*\]=*)
        local v="${kv#*=}"
        case "$v" in
          auto) has_auto=1 ;;
          strict) has_strict=1 ;;
          *) _pp_die 0 "unknown mode in modes[]: $v" ;;
        esac
        ;;
      release_gate.verbs\[*\]=*)
        local v="${kv#*=}"
        if [ "$v" = "edit" ]; then edit_in_release=1; fi
        if ! [[ "$v" =~ ^(approve|reject)$ ]]; then
          _pp_die 0 "release_gate.verbs must be subset of {approve, reject}: $v"
        fi
        ;;
      plan_gate_verbs\[*\]=*)
        local v="${kv#*=}"
        if ! [[ "$v" =~ $_PARSE_POLICY_VALID_VERBS_RE ]]; then
          _pp_die 0 "plan_gate_verbs has invalid verb: $v"
        fi
        ;;
      refactor_scope_threshold.files=*)
        files_thr="${kv#*=}"
        ;;
      refactor_scope_threshold.loc=*)
        loc_thr="${kv#*=}"
        ;;
      time_box.min_seconds=*)
        tb_min="${kv#*=}"
        ;;
      time_box.max_seconds=*)
        tb_max="${kv#*=}"
        ;;
    esac
  done

  if [ "$version" != "1" ]; then
    _pp_die 0 "version must be 1, got: ${version:-<missing>}"
  fi
  if [ "$has_auto" != "1" ] || [ "$has_strict" != "1" ]; then
    _pp_die 0 "modes must contain both 'auto' and 'strict'"
  fi
  if [ "$edit_in_release" = "1" ]; then
    _pp_die 0 "release_gate.verbs MUST NOT contain 'edit' (invariant 8)"
  fi
  if [ -n "$files_thr" ] && ! [[ "$files_thr" =~ ^[0-9]+$ ]]; then
    _pp_die 0 "refactor_scope_threshold.files must be a non-negative integer"
  fi
  if [ -n "$loc_thr" ] && ! [[ "$loc_thr" =~ ^[0-9]+$ ]]; then
    _pp_die 0 "refactor_scope_threshold.loc must be a non-negative integer"
  fi
  if [ -n "$tb_min" ] && [ -n "$tb_max" ]; then
    # Enforce positivity (invariant I6): zero-second time boxes are meaningless.
    if ! [[ "$tb_min" =~ ^[1-9][0-9]*$ ]] || ! [[ "$tb_max" =~ ^[1-9][0-9]*$ ]]; then
      _pp_die 0 "time_box seconds must be positive integers (got min=${tb_min} max=${tb_max})"
    fi
    if [ "$tb_min" -gt "$tb_max" ]; then
      _pp_die 0 "time_box.min_seconds > max_seconds"
    fi
  fi

  printf '%s\n' "${out[@]}"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  parse_approvals_policy "${1-}"
  exit $?
fi
