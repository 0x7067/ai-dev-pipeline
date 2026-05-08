#!/usr/bin/env bash
# resolve-run.sh — resolve the active RunId at fire time.
#
# Layer: BOUNDARY. Reads from up to three untrusted sources and parses
# the first hit through scripts/parse-run-id.sh. Never echoes a value
# that the parser would reject.
#
# Resolution order:
#   1. $RUN_ID environment variable, if set and non-empty.
#   2. .claude/workflow-state/active file content (orchestrator pointer).
#   3. docs/latest symlink target basename.
#   4. docs/latest.txt content.
#
# Output:
#   stdout: the validated run-id (one line, no trailing whitespace).
#   exit  : 0 on success; 1 if no source resolved; 2 if a source was
#           present but failed the parser (fail closed — never echo
#           untrusted data).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

# resolve_run_id: tries each source; on first non-empty source, parses.
# A non-empty source that fails parsing is FATAL (exit 2) — we do not
# silently fall through, because that would let an attacker who can
# write a poisoned RUN_ID env shadow a clean docs/latest.
resolve_run_id() {
  local candidate=""

  # Source 1: env
  if [ -n "${RUN_ID:-}" ]; then
    candidate="$RUN_ID"
  fi

  # Source 2: .claude/workflow-state/active
  if [ -z "$candidate" ] && [ -f ".claude/workflow-state/active" ]; then
    candidate=$(head -n1 ".claude/workflow-state/active" 2>/dev/null | tr -d '[:space:]')
  fi

  # Source 3: docs/latest symlink
  if [ -z "$candidate" ] && [ -L "docs/latest" ]; then
    local target
    target=$(readlink "docs/latest" 2>/dev/null || true)
    if [ -n "$target" ]; then
      candidate=$(basename "$target")
    fi
  fi

  # Source 4: docs/latest.txt
  if [ -z "$candidate" ] && [ -f "docs/latest.txt" ]; then
    candidate=$(head -n1 "docs/latest.txt" 2>/dev/null | tr -d '[:space:]')
  fi

  if [ -z "$candidate" ]; then
    printf 'resolve-run: ERROR: no active run-id (set RUN_ID or run /ship)\n' >&2
    return 1
  fi

  if ! parse_run_id "$candidate" >/dev/null; then
    printf 'resolve-run: ERROR: source returned an unparseable run-id (refusing to echo)\n' >&2
    return 2
  fi

  printf '%s\n' "$candidate"
  return 0
}

# resolve_run_dir: returns "docs/runs/<resolved-id>" if a run is active,
# otherwise the same exit-code semantics as resolve_run_id.
resolve_run_dir() {
  local id
  id=$(resolve_run_id) || return $?
  printf 'docs/runs/%s\n' "$id"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-id}" in
    id|"")    resolve_run_id ;;
    dir)      resolve_run_dir ;;
    *)        printf 'resolve-run: ERROR: unknown subcommand %q (use id|dir)\n' "$1" >&2; exit 2 ;;
  esac
  exit $?
fi
