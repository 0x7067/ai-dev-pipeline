#!/usr/bin/env bash
# Pure core: projections and validators over typed Spec records.
#
# Per .claude/rules/architecture-fcis.md, this file MUST NOT perform I/O.
# It only consumes already-parsed records (output of parse-spec.sh) and
# returns transformed records on stdout.
#
# Record format (input + output): one field per line, "<FIELD>\t<VALUE>",
# with newlines/tabs encoded as \n / \t.
#
# Functions:
#   spec_to_index_entry      — project a parsed Spec to its index row.
#   sort_specs               — deterministic sort of index records by id.
#   validate_spec_invariants — list invariant violations (one per line).
#   decode_value             — undo the parser's escape encoding.
#   html_escape              — escape a UTF-8 string for HTML body/attribute.

set -u

# Decode the parser's escape encoding back to literal bytes.
# Pure: stdin -> stdout, no globals touched.
decode_value() {
  # Order matters: \\ must be processed last to avoid re-decoding.
  local s="$1"
  s="${s//\\n/$'\n'}"
  s="${s//\\t/$'\t'}"
  s="${s//\\\\/\\}"
  printf '%s' "$s"
}

# HTML-escape minimum set (&, <, >, ", ').
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//\'/&#39;}"
  printf '%s' "$s"
}

# Extract a single scalar field value from a records blob.
spec_field() {
  local records="$1" field="$2"
  printf '%s\n' "$records" \
    | awk -F'\t' -v f="$field" '$1==f{print $2; found=1; exit} END{if(!found) exit 1}'
}

# Extract list field values, one per line, in original order.
spec_list() {
  local records="$1" field="$2"
  printf '%s\n' "$records" | awk -F'\t' -v f="$field" '$1==f{print $2}'
}

# spec_to_index_entry <records>
# Emit a 4-field index entry suitable for the index page.
spec_to_index_entry() {
  local records="$1"
  local id title status risk
  id="$(spec_field "$records" id || true)"
  title="$(spec_field "$records" title || true)"
  status="$(spec_field "$records" status || true)"
  risk="$(spec_field "$records" risk || true)"
  printf 'id\t%s\n' "$id"
  printf 'title\t%s\n' "$title"
  printf 'status\t%s\n' "$status"
  printf 'risk\t%s\n' "$risk"
  spec_list "$records" tags | while IFS='' read -r tag; do
    [[ -z "$tag" ]] && continue
    printf 'tag\t%s\n' "$tag"
  done
}

# sort_specs <list_of_paths_to_records_files>
# Pure with respect to its inputs (file contents). Reads each file, emits
# its (id, path) pair, sorts by id, prints sorted paths on stdout.
sort_specs() {
  local f
  for f in "$@"; do
    local id
    id="$(spec_field "$(cat "$f")" id || true)"
    printf '%s\t%s\n' "$id" "$f"
  done | LC_ALL=C sort -k1,1 | awk -F'\t' '{print $2}'
}

# validate_spec_invariants <records>
# Emits one violation per line. Exit 0 always — this is a pure
# diagnostic; the caller decides what to do with the list.
validate_spec_invariants() {
  local records="$1"
  local id status risk
  id="$(spec_field "$records" id 2>/dev/null || true)"
  status="$(spec_field "$records" status 2>/dev/null || true)"
  risk="$(spec_field "$records" risk 2>/dev/null || true)"
  if [[ -z "$id" ]]; then
    printf 'missing id\n'
  fi
  case "$status" in
    draft|accepted|superseded) ;;
    *) printf 'invalid status: %s\n' "$status" ;;
  esac
  case "$risk" in
    low|medium|high) ;;
    *) printf 'invalid risk: %s\n' "$risk" ;;
  esac
}
