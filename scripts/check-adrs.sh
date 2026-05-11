#!/usr/bin/env bash
# Validate lightweight ADR artifacts under docs/runs/<RUN_ID>/adrs/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

errors=0

note() {
  printf 'adrs: %s\n' "$*"
}

fail() {
  printf 'adrs: ERROR: %s\n' "$*" >&2
  errors=$((errors + 1))
}

default_adrs_glob() {
  if [ -n "${RUN_DIR:-}" ]; then
    printf '%s/adrs/*.md\n' "$RUN_DIR"
  elif [ -L "docs/latest" ] || [ -d "docs/latest" ]; then
    printf 'docs/latest/adrs/*.md\n'
  else
    printf 'docs/runs/*/adrs/*.md\n'
  fi
}

check_contains() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -Eq "$pattern" "$file"; then
    fail "$file missing $label"
  fi
}

check_section_body() {
  local file="$1"
  local section="$2"
  local next_section="${3-}"

  if ! awk -v section="$section" -v next_section="$next_section" '
    $0 == section { in_section = 1; next }
    next_section != "" && $0 == next_section && in_section { exit }
    in_section && $0 !~ /^[[:space:]]*$/ && $0 !~ /^#/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file"; then
    fail "$file has no body under $section"
  fi
}

check_adr_file() {
  local file="$1"
  local base
  base="$(basename "$file")"

  case "$base" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-*.md) ;;
    *) fail "$file filename must be YYYYMMDD-short-slug.md" ;;
  esac

  if [ ! -s "$file" ]; then
    fail "$file is empty"
    return
  fi

  check_contains "$file" '^# ADR: .+' 'title heading'
  check_contains "$file" '^Status: (proposed|accepted|superseded)$' 'Status metadata'
  check_contains "$file" '^Date: [0-9]{4}-[0-9]{2}-[0-9]{2}$' 'Date metadata'
  check_contains "$file" '^Run: .+' 'Run metadata'
  check_contains "$file" '^## Context$' 'Context section'
  check_contains "$file" '^## Decision$' 'Decision section'
  check_contains "$file" '^## Consequences$' 'Consequences section'
  check_section_body "$file" '## Context' '## Decision'
  check_section_body "$file" '## Decision' '## Consequences'
  check_section_body "$file" '## Consequences'

  if grep -Eq '<(short decision title|RUN_ID)>' "$file"; then
    fail "$file still contains template placeholder text"
  fi
}

adrs_glob="${WORKFLOW_ADRS_GLOB:-$(default_adrs_glob)}"

# shellcheck disable=SC2206 # intentional glob expansion
adr_files=($adrs_glob)
if [ "${adr_files[0]}" = "$adrs_glob" ]; then
  note "OK (no ADR artifacts present)"
  exit 0
fi

for adr_file in "${adr_files[@]}"; do
  [ -f "$adr_file" ] || continue
  check_adr_file "$adr_file"
done

if [ "$errors" -gt 0 ]; then
  note "FAILED with $errors issue(s)"
  exit 1
fi

note "OK (${#adr_files[@]} file(s))"
exit 0
