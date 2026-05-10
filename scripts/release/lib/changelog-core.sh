#!/usr/bin/env bash
# changelog-core.sh — pure functions over an already-parsed CHANGELOG.
#
# FC/IS placement: CORE. Operates only on parsed records emitted by
# scripts/release/parse-changelog.sh. No file I/O.
#
# Public API:
#
#   infer_bump_from_changelog <records-stdin>
#       Reads typed parser records (see parse-changelog.sh "Output protocol")
#       from stdin and prints exactly one of: major | minor | patch.
#       Mapping:
#         - any "Removed" or any entry under a "BREAKING" tag -> major
#         - any "Added" or "Changed"                          -> minor
#         - otherwise (only Fixed / Security / Deprecated /
#           Docs)                                              -> patch
#       The function reads only the topmost section (label "Unreleased"
#       OR a SemVer label); subsequent sections are ignored by the parser
#       contract upstream.
#
# Record format consumed (one per line, TAB-separated):
#   section_label   <Unreleased|x.y.z>
#   section_date    <YYYY-MM-DD|->                # "-" for Unreleased
#   entry           <kind>\t<text>                # kind ∈ Added|Changed|Fixed|Removed|Deprecated|Security|Docs

# shellcheck shell=bash

if [[ -n "${_CHANGELOG_CORE_LOADED:-}" ]]; then return 0; fi
_CHANGELOG_CORE_LOADED=1

infer_bump_from_changelog() {
  local saw_added=0 saw_changed=0 saw_removed=0 saw_breaking=0
  local field rest kind text
  while IFS=$'\t' read -r field rest; do
    [[ -z "$field" ]] && continue
    if [[ "$field" == "entry" ]]; then
      # rest = "<kind>\t<text>"
      kind="${rest%%	*}"
      text="${rest#*	}"
      case "$kind" in
        Added)      saw_added=1 ;;
        Changed)    saw_changed=1 ;;
        Removed)    saw_removed=1 ;;
        Fixed|Security|Deprecated|Docs) : ;;
      esac
      # BREAKING marker: "[BREAKING]" or leading "BREAKING:" in entry text.
      case "$text" in
        *'[BREAKING]'*|'BREAKING:'*|'BREAKING CHANGE:'*) saw_breaking=1 ;;
      esac
    fi
  done

  if (( saw_removed || saw_breaking )); then
    echo "major"
  elif (( saw_added || saw_changed )); then
    echo "minor"
  else
    echo "patch"
  fi
}
