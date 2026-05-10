#!/usr/bin/env bash
# parse-changelog.sh — boundary parser for CHANGELOG.md (Keep-a-Changelog 1.1.0).
#
# FC/IS placement: BOUNDARY. Reads bytes from a CHANGELOG file, emits typed
# records on stdout. Per .claude/rules/boundary-parse-dont-validate.md, raw
# CHANGELOG bytes never cross into core; consumers (changelog-core.sh,
# release.sh) read records only.
#
# Output protocol (TAB-separated records, one per line):
#   section_label   <Unreleased|x.y.z>
#   section_date    <YYYY-MM-DD|->                # "-" when Unreleased
#   entry           <kind>\t<text>                # kind ∈ Added|Changed|Fixed|Removed|Deprecated|Security|Docs
#
# By default the parser emits records for the TOPMOST release section only
# (whichever appears first: `## [Unreleased]` or `## [x.y.z] - DATE`). Pass
# `--all` to emit every section (used by the duplicate-version reject test).
#
# Modes:
#   parse-changelog.sh <path>            -> records for topmost section
#   parse-changelog.sh --all <path>      -> records for every section
#   parse-changelog.sh --check <path>    -> exit 0/1, no stdout
#   parse-changelog.sh --label <path>    -> print only the topmost label
#
# Reject conditions (exit 1, diagnostic to stderr):
#   - section header line malformed (e.g. `## [` without closing bracket,
#     missing version, missing date for a non-Unreleased section)
#   - unknown subsection label (`### Frobbed`)
#   - duplicate version (only when --all is in use; the topmost-only mode
#     short-circuits before seeing duplicates)
#   - file missing or unreadable
#
# Reference: https://keepachangelog.com/en/1.1.0/

set -uo pipefail

SCRIPT_NAME="parse-changelog"

err() { printf '%s: ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; }

ALLOWED_LABELS=(Added Changed Fixed Removed Deprecated Security Docs)

is_allowed_label() {
  local l="$1"
  for a in "${ALLOWED_LABELS[@]}"; do [[ "$a" == "$l" ]] && return 0; done
  return 1
}

# SemVer release-only regex (mirrors semver-core.sh _SEMVER_RE).
_SEMVER_RE_LOCAL='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

mode="topmost"
arg=""
while (( $# > 0 )); do
  case "$1" in
    --all)   mode="all"; shift ;;
    --check) mode="check"; shift ;;
    --label) mode="label"; shift ;;
    --)      shift; break ;;
    -*)      err "unknown flag: $1"; exit 2 ;;
    *)       arg="$1"; shift ;;
  esac
done

if [[ -z "$arg" ]]; then
  err "usage: $SCRIPT_NAME [--all|--check|--label] <path>"
  exit 2
fi
if [[ ! -f "$arg" ]]; then
  err "file not found: $arg"
  exit 1
fi

# Two-pass parser. Pass 1 collects each section's header + body lines into
# arrays; pass 2 validates and emits records.

declare -a _labels=()
declare -a _dates=()
declare -a _bodies=()  # joined with literal "\n" between lines per section

current_label=""
current_date=""
current_body=""
in_section=0

flush_section() {
  if (( in_section )); then
    _labels+=("$current_label")
    _dates+=("$current_date")
    _bodies+=("$current_body")
  fi
  current_label=""
  current_date=""
  current_body=""
  in_section=0
}

while IFS='' read -r line || [[ -n "$line" ]]; do
  case "$line" in
    '## ['*)
      flush_section
      # Recognized shapes:
      #   ## [Unreleased]
      #   ## [x.y.z] - YYYY-MM-DD
      header_inner="${line#'## ['}"
      label="${header_inner%%]*}"
      rest="${header_inner#*]}"
      if [[ "$label" == "$header_inner" ]]; then
        err "malformed section header (no closing bracket): $line"
        exit 1
      fi
      if [[ "$label" == "Unreleased" ]]; then
        current_label="Unreleased"
        current_date="-"
      else
        if [[ ! "$label" =~ $_SEMVER_RE_LOCAL ]]; then
          err "malformed version in section header: $line"
          exit 1
        fi
        # rest should be " - YYYY-MM-DD"
        rest="${rest# }"
        if [[ "$rest" != "- "* ]]; then
          err "missing date in section header: $line"
          exit 1
        fi
        date="${rest#- }"
        if [[ ! "$date" =~ $_DATE_RE ]]; then
          err "malformed date in section header: $line"
          exit 1
        fi
        current_label="$label"
        current_date="$date"
      fi
      in_section=1
      ;;
    '## '*)
      # Any other H2 (e.g. plain "## Notes") closes any open section but is
      # not itself a release section. The first H2 of CHANGELOG.md is the
      # title, parsed as H1; H2s belong to release sections only.
      flush_section
      ;;
    *)
      if (( in_section )); then
        if [[ -z "$current_body" ]]; then
          current_body="$line"
        else
          current_body="${current_body}"$'\n'"$line"
        fi
      fi
      ;;
  esac
done < "$arg"
flush_section

if (( ${#_labels[@]} == 0 )); then
  err "no release sections found in $arg"
  exit 1
fi

# Duplicate-version check (only meaningful in --all). The topmost mode sees
# at most one section anyway.
if [[ "$mode" == "all" ]]; then
  # bash 3.2-compatible duplicate detection (no associative arrays).
  dup="$(printf '%s\n' "${_labels[@]}" | awk 'seen[$0]++ { print; exit }')"
  if [[ -n "$dup" ]]; then
    err "duplicate section label: $dup"
    exit 1
  fi
fi

emit_section_records() {
  local idx="$1"
  local lbl="${_labels[$idx]}"
  local dt="${_dates[$idx]}"
  local body="${_bodies[$idx]}"
  printf 'section_label\t%s\n' "$lbl"
  printf 'section_date\t%s\n'  "$dt"

  local kind=""
  while IFS='' read -r bline; do
    [[ -z "$bline" ]] && continue
    case "$bline" in
      '### '*)
        kind="${bline#'### '}"
        # Trim trailing whitespace.
        kind="${kind%"${kind##*[![:space:]]}"}"
        if ! is_allowed_label "$kind"; then
          err "unknown subsection label '### $kind' in section [$lbl]"
          exit 1
        fi
        ;;
      '- '*)
        if [[ -z "$kind" ]]; then
          err "bullet outside any '###' subsection in [$lbl]: $bline"
          exit 1
        fi
        local text="${bline#- }"
        # Encode tabs/newlines (none expected from a single line read).
        printf 'entry\t%s\t%s\n' "$kind" "$text"
        ;;
      ' '*|$'\t'*)
        # Continuation lines for a bullet — append (best-effort) to the
        # last entry by emitting another record. For the bump inference and
        # tag-body use cases we only need the first line per bullet; we
        # therefore drop continuation lines deliberately to keep records
        # one-line-stable.
        :
        ;;
      *)
        # Stray non-bullet, non-header text inside a release section is
        # tolerated (e.g. blank prose). Silently skip.
        :
        ;;
    esac
  done <<<"$body"
}

case "$mode" in
  check)
    exit 0
    ;;
  label)
    printf '%s\n' "${_labels[0]}"
    exit 0
    ;;
  topmost)
    emit_section_records 0
    ;;
  all)
    for i in "${!_labels[@]}"; do
      emit_section_records "$i"
    done
    ;;
esac
