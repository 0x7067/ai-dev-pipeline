#!/usr/bin/env bash
# parse-release-state.sh — boundary parser for the release state sidecar.
#
# FC/IS placement: BOUNDARY. Reads an untrusted JSON file produced by
# `scripts/release/release.sh` between halts and emits a typed record on
# stdout. Rejects malformed input. Fail closed.
#
# Output (on success): one line per field, in fixed order, TAB-separated
# key/value pairs. Phase determines which fields are present.
#
#   phase   <pending-version-confirm|phase-b-complete>
#   bump    <patch|minor|major>
#   current <X.Y.Z>
#   proposed <X.Y.Z>
#   target_version <X.Y.Z>   # only when phase=phase-b-complete
#   tag     v<X.Y.Z>         # only when phase=phase-b-complete
#
# Usage: parse-release-state.sh <state-file>
#
# Exit: 0 on accept, 1 on reject with a structured `release: ERROR: …` line
# on stderr identifying the offending field.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/release/lib/semver-core.sh
source "$SCRIPT_DIR/lib/semver-core.sh"

err() { printf 'release: ERROR: parse-release-state: %s\n' "$*" >&2; }

main() {
  local path="${1:-}"
  if [[ -z "$path" ]]; then
    err "missing state-file path argument"; return 1
  fi
  if [[ ! -f "$path" ]]; then
    err "state file '$path' does not exist or is not a regular file"; return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    err "jq is required"; return 1
  fi

  # Reject non-JSON / empty.
  if ! jq -e . "$path" >/dev/null 2>&1; then
    err "state file '$path' is not valid JSON"; return 1
  fi

  local phase bump current proposed target_version tag
  phase="$(jq -r '.phase // ""' "$path")"
  bump="$(jq -r '.bump // ""' "$path")"
  current="$(jq -r '.current // ""' "$path")"
  proposed="$(jq -r '.proposed // ""' "$path")"

  case "$phase" in
    pending-version-confirm|phase-b-complete) ;;
    "") err "missing required field: phase"; return 1 ;;
    *)  err "unknown phase value: '$phase' (expected pending-version-confirm|phase-b-complete)"; return 1 ;;
  esac

  case "$bump" in
    patch|minor|major) ;;
    "") err "missing required field: bump"; return 1 ;;
    *)  err "invalid bump value: '$bump' (expected patch|minor|major)"; return 1 ;;
  esac

  if [[ -z "$current" ]]; then
    err "missing required field: current"; return 1
  fi
  if ! parse_semver "$current" >/dev/null; then
    err "field 'current' is not a release SemVer: '$current'"; return 1
  fi

  if [[ -z "$proposed" ]]; then
    err "missing required field: proposed"; return 1
  fi
  if ! parse_semver "$proposed" >/dev/null; then
    err "field 'proposed' is not a release SemVer: '$proposed'"; return 1
  fi

  if [[ "$phase" == "phase-b-complete" ]]; then
    target_version="$(jq -r '.target_version // ""' "$path")"
    tag="$(jq -r '.tag // ""' "$path")"
    if [[ -z "$target_version" ]]; then
      err "phase=phase-b-complete requires field 'target_version'"; return 1
    fi
    if ! parse_semver "$target_version" >/dev/null; then
      err "field 'target_version' is not a release SemVer: '$target_version'"; return 1
    fi
    if [[ -z "$tag" ]]; then
      err "phase=phase-b-complete requires field 'tag'"; return 1
    fi
    if [[ "$tag" != "v$target_version" ]]; then
      err "field 'tag'='$tag' does not match 'v\$target_version'='v$target_version'"; return 1
    fi
  fi

  printf 'phase\t%s\n' "$phase"
  printf 'bump\t%s\n'  "$bump"
  printf 'current\t%s\n' "$current"
  printf 'proposed\t%s\n' "$proposed"
  if [[ "$phase" == "phase-b-complete" ]]; then
    printf 'target_version\t%s\n' "$target_version"
    printf 'tag\t%s\n' "$tag"
  fi
}

main "$@"
