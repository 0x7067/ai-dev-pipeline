#!/usr/bin/env bash
# Boundary parser: docs/specs/<id>/spec.yaml -> typed Spec record.
#
# This is the ONLY entry point any consumer should use to read a spec
# file. Per .claude/rules/boundary-parse-dont-validate.md, raw YAML bytes
# never cross into core. The parser fails closed on:
#   - missing required fields
#   - unknown top-level fields
#   - id ↔ path mismatch (INV-5)
#   - malformed list/scalar lines
#
# Output protocol (stdout):
#   One record per line: <FIELD><TAB><VALUE>
#   - Scalar fields: emitted once. Newlines inside block scalars are
#     encoded as the literal two-character sequence "\n". Tabs as "\t".
#     Backslashes as "\\".
#   - List fields: emitted once per item with the same FIELD prefix.
#
# Recognised top-level fields:
#   scalar : id, title, status, risk, summary, motivation, scope, body_path
#   list   : tags, acceptance_criteria, invariants, boundary_map, references
#
# A small companion entry point parses docs/specs/index.yaml:
#   parse_spec_index <path>  -> records: index.spec.<n>.<field>=<value>
#
# Usage:
#   scripts/specs/parse-spec.sh <path-to-spec.yaml>          # parse one spec
#   scripts/specs/parse-spec.sh --index <path-to-index.yaml> # parse index
#   scripts/specs/parse-spec.sh --check <path-to-spec.yaml>  # exit 0/1 only

set -euo pipefail

SCRIPT_NAME="parse-spec"

err() { printf '%s: ERROR: %s\n' "${SCRIPT_NAME}" "$*" >&2; }

# Encode a value so it survives one record per line. Newlines, tabs, and
# backslashes only — keep this stable for downstream decoders.
encode_value() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

emit() {
  local field="$1" value="$2"
  printf '%s\t%s\n' "$field" "$(encode_value "$value")"
}

# Allowed top-level fields (kept here as the schema source of truth).
SCALAR_FIELDS=(id title status risk summary motivation scope body_path)
LIST_FIELDS=(tags acceptance_criteria invariants boundary_map references)
ALL_FIELDS=("${SCALAR_FIELDS[@]}" "${LIST_FIELDS[@]}")

is_scalar_field() {
  local f="$1"
  for s in "${SCALAR_FIELDS[@]}"; do [[ "$s" == "$f" ]] && return 0; done
  return 1
}

is_list_field() {
  local f="$1"
  for s in "${LIST_FIELDS[@]}"; do [[ "$s" == "$f" ]] && return 0; done
  return 1
}

is_known_field() {
  local f="$1"
  for s in "${ALL_FIELDS[@]}"; do [[ "$s" == "$f" ]] && return 0; done
  return 1
}

# parse_spec_file <path>
#
# Reads YAML and emits typed records on stdout. Exits non-zero on any
# parse failure with a structured stderr message. The required-field
# check is run after parsing.
parse_spec_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    err "spec file not found: $path"
    return 2
  fi

  # Track which fields have been seen so we can fail closed on missing
  # required fields and on duplicates. bash 3 lacks associative arrays;
  # use a space-padded string as a small set: " field1 field2 ".
  local seen=" "
  _seen_has() { case "$seen" in *" $1 "*) return 0;; *) return 1;; esac; }
  _seen_add() { seen+="$1 "; }

  local current_field=""
  local current_mode=""   # one of: scalar, block, list, ""
  local block_buf=""
  local block_first=1
  local list_empty=0
  local BLOCK_INDENT=""

  flush_block() {
    if [[ "$current_mode" == "block" && -n "$current_field" ]]; then
      # Trim a single trailing newline (YAML | behaviour, simplified).
      local v="$block_buf"
      v="${v%$'\n'}"
      emit "$current_field" "$v"
      block_buf=""
      block_first=1
    fi
  }

  local line raw
  local lineno=0
  while IFS='' read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    raw="$line"

    # Skip blank lines unless we are inside a block scalar (preserve them).
    if [[ "$current_mode" == "block" ]]; then
      if [[ -z "${raw// }" ]]; then
        block_buf+=$'\n'
        continue
      fi
      # Determine indentation of block scalar from first non-empty line.
      if [[ "$block_first" == "1" ]]; then
        # Capture leading whitespace (spaces only; tabs not allowed).
        local leading="${raw%%[! ]*}"
        if [[ -z "$leading" ]]; then
          # Block ended (no indentation) — flush and re-process this line below.
          flush_block
          current_mode=""
          current_field=""
        else
          BLOCK_INDENT="$leading"
          block_buf="${raw#"$BLOCK_INDENT"}"
          block_first=0
          continue
        fi
      else
        # Subsequent lines: must be indented at least BLOCK_INDENT.
        if [[ "$raw" == "$BLOCK_INDENT"* ]]; then
          block_buf+=$'\n'
          block_buf+="${raw#"$BLOCK_INDENT"}"
          continue
        else
          # Dedent → end of block.
          flush_block
          current_mode=""
          current_field=""
          # fall through to re-process this line as top-level
        fi
      fi
    fi

    # Comment / blank handling at top level.
    if [[ -z "${raw// }" ]]; then continue; fi
    # Strip trailing CR (in case of CRLF).
    raw="${raw%$'\r'}"
    # Full-line comment.
    if [[ "${raw#"${raw%%[! ]*}"}" == \#* ]]; then continue; fi

    # List-item continuation? Two-space indent + "- ".
    if [[ "$current_mode" == "list" && "$raw" =~ ^[[:space:]]+-[[:space:]]+(.*)$ ]]; then
      local item="${BASH_REMATCH[1]}"
      # Strip a possible trailing inline comment (only when preceded by space).
      # Conservative: do NOT strip inside quoted strings — we don't accept those.
      emit "$current_field" "$item"
      list_empty=0
      continue
    fi

    # Otherwise this line should be a top-level "key:" or "key: value".
    if [[ "$raw" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local rhs="${BASH_REMATCH[2]}"
      # Close any list that was open without items.
      if [[ "$current_mode" == "list" && "$list_empty" == "1" ]]; then
        # Empty list — emit a single sentinel? No: simply emit no items.
        :
      fi
      current_mode=""
      current_field=""

      if ! is_known_field "$key"; then
        err "$path:$lineno: unknown field: $key"
        return 1
      fi
      if _seen_has "$key"; then
        err "$path:$lineno: duplicate field: $key"
        return 1
      fi
      _seen_add "$key"

      # Trim leading space from rhs.
      rhs="${rhs# }"

      if is_scalar_field "$key"; then
        if [[ "$rhs" == "|" ]]; then
          current_field="$key"
          current_mode="block"
          block_buf=""
          block_first=1
        elif [[ -n "$rhs" ]]; then
          emit "$key" "$rhs"
        else
          err "$path:$lineno: scalar field '$key' has no value (use '| <newline>' for block scalar)"
          return 1
        fi
      elif is_list_field "$key"; then
        if [[ -z "$rhs" ]]; then
          current_field="$key"
          current_mode="list"
          list_empty=1
        elif [[ "$rhs" == "[]" ]]; then
          # Empty inline list — record nothing but mark as seen.
          :
        else
          err "$path:$lineno: list field '$key' must be on its own line (use '$key:' followed by '  - item' lines, or '[]' for empty)"
          return 1
        fi
      fi
      continue
    fi

    err "$path:$lineno: unrecognised line (expected 'key:' or '  - item'): $raw"
    return 1
  done < "$path"

  flush_block

  # Required scalar fields.
  local required=(id title status risk summary motivation scope)
  local f
  for f in "${required[@]}"; do
    if ! _seen_has "$f"; then
      err "$path: missing required field: $f"
      return 1
    fi
  done
  # acceptance_criteria, invariants, boundary_map, references must be
  # declared (may be empty list).
  for f in acceptance_criteria invariants boundary_map references; do
    if ! _seen_has "$f"; then
      err "$path: missing required list field: $f"
      return 1
    fi
  done

  return 0
}

# Validate id ↔ path invariant (INV-5).
check_id_path() {
  local path="$1"
  local records="$2"
  local id_value
  id_value="$(printf '%s\n' "$records" | awk -F'\t' '$1=="id"{print $2; exit}')"
  if [[ -z "$id_value" ]]; then
    err "$path: id field is empty after parse"
    return 1
  fi
  local dir_name
  dir_name="$(basename "$(dirname "$path")")"
  if [[ "$id_value" != "$dir_name" ]]; then
    err "$path: id ($id_value) does not match directory ($dir_name) — violates INV-5"
    return 1
  fi
  # status whitelist
  local status_value
  status_value="$(printf '%s\n' "$records" | awk -F'\t' '$1=="status"{print $2; exit}')"
  case "$status_value" in
    draft|accepted|superseded) ;;
    *)
      err "$path: invalid status: '$status_value' (expected: draft|accepted|superseded)"
      return 1
      ;;
  esac
  # risk whitelist
  local risk_value
  risk_value="$(printf '%s\n' "$records" | awk -F'\t' '$1=="risk"{print $2; exit}')"
  case "$risk_value" in
    low|medium|high) ;;
    *)
      err "$path: invalid risk: '$risk_value' (expected: low|medium|high)"
      return 1
      ;;
  esac
  return 0
}

# parse_spec <path> — full pipeline (parse + structural checks). Emits
# records on stdout, exits non-zero on failure.
parse_spec() {
  local path="$1"
  local out
  if ! out="$(parse_spec_file "$path")"; then
    return 1
  fi
  if ! check_id_path "$path" "$out"; then
    return 1
  fi
  printf '%s\n' "$out"
}

# parse_spec_index <path> — the index is structurally simpler: a single
# top-level 'specs:' list, each item being a small map with id/title/
# status/risk/tags. We re-use the per-item parser by extracting blocks.
parse_spec_index() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    err "index file not found: $path"
    return 2
  fi
  local lineno=0
  local in_specs=0
  local cur_n=-1
  local line
  # Track ids seen so we can fail closed on duplicates. Space-padded
  # string used as a small set: " id1 id2 ".
  local seen_ids=" "
  while IFS='' read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    # full-line comment / blank
    local stripped="${line#"${line%%[! ]*}"}"
    if [[ -z "$stripped" || "$stripped" == \#* ]]; then continue; fi

    if [[ "$line" =~ ^specs:[[:space:]]*$ ]]; then
      in_specs=1
      continue
    fi
    if [[ "$in_specs" != "1" ]]; then
      err "$path:$lineno: expected 'specs:' as first top-level key"
      return 1
    fi
    # New spec item: "  - id: value"
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+id:[[:space:]]*(.+)$ ]]; then
      cur_n=$((cur_n + 1))
      local id_value="${BASH_REMATCH[1]}"
      case "$seen_ids" in
        *" $id_value "*)
          err "$path:$lineno: duplicate spec id in index: $id_value"
          return 1
          ;;
      esac
      seen_ids+="$id_value "
      printf 'index.spec.%d.id\t%s\n' "$cur_n" "$(encode_value "$id_value")"
      continue
    fi
    # Field: "    title: value" / status / risk
    if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
      local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
      if [[ "$cur_n" -lt 0 ]]; then
        err "$path:$lineno: field '$k' before any '- id:' item"
        return 1
      fi
      case "$k" in
        title|status|risk)
          if [[ -z "$v" ]]; then
            err "$path:$lineno: field '$k' must have a scalar value"
            return 1
          fi
          printf 'index.spec.%d.%s\t%s\n' "$cur_n" "$k" "$(encode_value "$v")"
          ;;
        tags)
          # tags must be empty-rhs followed by indented list items
          if [[ -n "$v" && "$v" != "[]" ]]; then
            err "$path:$lineno: 'tags' must be a list (use '[]' for empty)"
            return 1
          fi
          ;;
        id)
          err "$path:$lineno: duplicate 'id' for current spec entry"
          return 1
          ;;
        *)
          err "$path:$lineno: unknown index field: $k"
          return 1
          ;;
      esac
      continue
    fi
    # Tag list item: "      - tagname"
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.+)$ ]]; then
      if [[ "$cur_n" -lt 0 ]]; then
        err "$path:$lineno: list item before any '- id:' entry"
        return 1
      fi
      printf 'index.spec.%d.tag\t%s\n' "$cur_n" "$(encode_value "${BASH_REMATCH[1]}")"
      continue
    fi
    err "$path:$lineno: unrecognised index line: $line"
    return 1
  done < "$path"
  if [[ "$in_specs" != "1" ]]; then
    err "$path: missing top-level 'specs:' key"
    return 1
  fi
  return 0
}

# CLI entry.
main() {
  if [[ $# -lt 1 ]]; then
    err "usage: $0 [--check|--index] <path>"
    return 2
  fi
  case "$1" in
    --index)
      shift
      parse_spec_index "$1"
      ;;
    --check)
      shift
      parse_spec "$1" >/dev/null
      ;;
    -h|--help)
      cat <<EOF
$SCRIPT_NAME — boundary parser for docs/specs/<id>/spec.yaml

usage:
  $0 <path-to-spec.yaml>          # parse one spec, emit field records
  $0 --index <docs/specs/index.yaml>
  $0 --check <path-to-spec.yaml>  # exit 0 if valid, non-zero otherwise

records on stdout: <FIELD><TAB><VALUE>, with \\n / \\t / \\\\ encoding.
EOF
      ;;
    *)
      parse_spec "$1"
      ;;
  esac
}

# Only run main when invoked as a script (allow sourcing for tests).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
