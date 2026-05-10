#!/usr/bin/env bash
# semver-core.sh — pure SemVer 2.0.0 helpers.
#
# FC/IS placement: CORE. No I/O, no ambient state. Pure string functions.
# Source it; do not exec it.
#
# Public API (all functions print to stdout, return 0 on success, 1 on
# malformed input, and never modify globals other than _SEMVER_*):
#
#   parse_semver "<str>"
#       -> prints "<major> <minor> <patch>" (space-separated) on stdout.
#       -> rejects pre-release / build identifiers (deferred per plan §
#          Non-Goals: pre-release identifiers).
#
#   format_semver <major> <minor> <patch>
#       -> prints "<major>.<minor>.<patch>".
#
#   next_version "<current>" "<bump_kind>"
#       bump_kind ∈ {patch,minor,major}
#       -> prints the next version. Postcondition (I2): result > current.
#
# Reference: https://semver.org/spec/v2.0.0.html

# shellcheck shell=bash

if [[ -n "${_SEMVER_CORE_LOADED:-}" ]]; then return 0; fi
_SEMVER_CORE_LOADED=1

# Strict SemVer release-only regex: MAJOR.MINOR.PATCH, no leading zeros,
# no pre-release, no build metadata.
_SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

parse_semver() {
  local s="${1:-}"
  if [[ ! "$s" =~ $_SEMVER_RE ]]; then
    return 1
  fi
  printf '%s %s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

format_semver() {
  local major="${1:-}" minor="${2:-}" patch="${3:-}"
  # Precondition: each component is a non-negative decimal without leading
  # zeros (or a literal "0"). Caller's responsibility.
  case "$major$minor$patch" in
    *[!0-9]*) return 1 ;;
  esac
  [[ -z "$major" || -z "$minor" || -z "$patch" ]] && return 1
  printf '%d.%d.%d\n' "$major" "$minor" "$patch"
}

next_version() {
  local current="${1:-}" bump="${2:-}"
  local parts major minor patch
  if ! parts="$(parse_semver "$current")"; then return 1; fi
  read -r major minor patch <<<"$parts"
  case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *)     return 1 ;;
  esac
  format_semver "$major" "$minor" "$patch"
}

# Compare two semvers. Echoes -1 / 0 / 1 (current < / == / > other).
compare_semver() {
  local a b
  if ! a="$(parse_semver "${1:-}")"; then return 1; fi
  if ! b="$(parse_semver "${2:-}")"; then return 1; fi
  local a1 a2 a3 b1 b2 b3
  read -r a1 a2 a3 <<<"$a"
  read -r b1 b2 b3 <<<"$b"
  if (( a1 != b1 )); then
    if (( a1 > b1 )); then echo 1; else echo -1; fi
  elif (( a2 != b2 )); then
    if (( a2 > b2 )); then echo 1; else echo -1; fi
  elif (( a3 != b3 )); then
    if (( a3 > b3 )); then echo 1; else echo -1; fi
  else
    echo 0
  fi
}
