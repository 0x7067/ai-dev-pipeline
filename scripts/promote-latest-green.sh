#!/usr/bin/env bash
# promote-latest-green.sh — advance the `latest-green` pointer set when a run
# ends in a fully green state (verifier `go` AND reviewer `blocking=0`).
#
# Layer split per .claude/rules/architecture-fcis.md:
#   CORE      : should_promote (sourced from scripts/lib/promote-core.sh).
#   BOUNDARY  : parse_args — allowlists --verify-status, regex-checks
#               --review-blocking, routes --run-id through parse-run-id.sh.
#   SHELL     : confirms docs/aidp/runs/<id> exists and atomically updates the
#               three pointer files (mirrors atomic_update_latest in
#               mint-run-id.sh — `ln -sfn` + `mv` with per-process tmp).
#
# Strict additivity: this script never reads or writes the existing
# `docs/aidp/latest`, `docs/aidp/latest.txt`, or `active` pointers. Failure is
# non-blocking by convention; the orchestrator catches non-zero exit codes.
#
# Usage:
#   scripts/promote-latest-green.sh --run-id <id> \
#     --verify-status <go|no-go|fail> --review-blocking <n>
#
# Exit codes:
#   0  promotion done OR no-op skip (non-green inputs).
#   2  bad arguments (boundary parser rejection).
#   3  --run-id valid but docs/aidp/runs/<id> directory does not exist.
#   >0 filesystem write failure (propagated from `mv`/`ln`).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"
# shellcheck source=scripts/lib/promote-core.sh
source "${SCRIPT_DIR}/lib/promote-core.sh"
# shellcheck source=scripts/lib/project-root.sh
source "${SCRIPT_DIR}/lib/project-root.sh"
# shellcheck source=scripts/lib/style.sh
source "${SCRIPT_DIR}/lib/style.sh"

# ---- boundary ----------------------------------------------------------------

usage() {
  cat <<'EOF'
promote-latest-green.sh — advance docs/aidp/latest-green pointer set on green runs.

Usage:
  promote-latest-green.sh --run-id <id> \
                          --verify-status <go|no-go|fail> \
                          --review-blocking <non-negative-int>
  promote-latest-green.sh --help

Behavior:
  - No-op (rc=0) unless verify-status=go AND review-blocking=0.
  - Refuses to advance a pointer at a missing target (rc=3).
  - Writes are atomic (tmp + mv with per-process suffix).
  - Never touches docs/aidp/latest, docs/aidp/latest.txt, or .claude/workflow-state/active.
EOF
}

VERIFY_STATUS_ALLOWED='go|no-go|fail'

parse_verify_status() {
  local v="${1-}"
  case "$v" in
    go|no-go|fail) printf '%s' "$v"; return 0 ;;
    *)
      printf 'promote-latest-green: ERROR: --verify-status must be one of {%s} (got %q)\n' \
        "$VERIFY_STATUS_ALLOWED" "$v" >&2
      return 2 ;;
  esac
}

parse_review_blocking() {
  local v="${1-}"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%s' "$v"
    return 0
  fi
  printf 'promote-latest-green: ERROR: --review-blocking must be a non-negative integer (got %q)\n' \
    "$v" >&2
  return 2
}

# ---- shell -------------------------------------------------------------------

# atomic_update_green_symlink <id> <docs_root>
#   Writes docs/aidp/latest-green -> runs/<id> (relative target) atomically.
atomic_update_green_symlink() {
  local id="$1" docs_root="$2"
  local suffix="$$.${RANDOM:-0}"
  local rel_target="runs/$id"
  ( cd "$docs_root" && ln -sfn "$rel_target" "latest-green.tmp.$suffix" \
      && mv "latest-green.tmp.$suffix" "latest-green" )
}

# atomic_update_green_text <id> <docs_root>
atomic_update_green_text() {
  local id="$1" docs_root="$2"
  local suffix="$$.${RANDOM:-0}"
  printf '%s\n' "$id" > "$docs_root/latest-green.txt.tmp.$suffix"
  mv "$docs_root/latest-green.txt.tmp.$suffix" "$docs_root/latest-green.txt"
}

# atomic_update_active_green <id> <ws_root>
atomic_update_active_green() {
  local id="$1" ws_root="$2"
  local suffix="$$.${RANDOM:-0}"
  mkdir -p "$ws_root"
  printf '%s\n' "$id" > "$ws_root/active-green.tmp.$suffix"
  mv "$ws_root/active-green.tmp.$suffix" "$ws_root/active-green"
}

# ---- entrypoint --------------------------------------------------------------

main() {
  local run_id="" verify_status="" review_blocking=""
  # Roots are resolved AFTER arg parsing so the CLI test hooks
  # --docs-root and --ws-root act as the first boundary step — if either
  # is supplied, no resolver call is made for that root.
  local docs_root="" ws_root=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) usage; return 0 ;;
      --run-id) run_id="${2-}"; shift 2 ;;
      --verify-status) verify_status="${2-}"; shift 2 ;;
      --review-blocking) review_blocking="${2-}"; shift 2 ;;
      --docs-root) docs_root="${2-}"; shift 2 ;;        # test hook
      --ws-root) ws_root="${2-}"; shift 2 ;;            # test hook
      *)
        printf 'promote-latest-green: ERROR: unknown arg %q\n' "$1" >&2
        return 2 ;;
    esac
  done

  # Resolve defaults only for roots the caller did not provide. Anchors
  # to the consumer project (or the plugin itself for self-tests), never
  # to cwd-relative paths.
  if [ -z "$docs_root" ] || [ -z "$ws_root" ]; then
    local _proj
    _proj="${AIDP_PROJECT_ROOT:-$(aidp_resolve_project_root)}" || {
      printf 'promote-latest-green: ERROR: could not resolve AIDP_PROJECT_ROOT\n' >&2
      return 2; }
    if [ -z "$docs_root" ]; then
      docs_root="${AIDP_ARTIFACTS_ROOT:-$(aidp_resolve_artifacts_root "$_proj")}" || {
        printf 'promote-latest-green: ERROR: could not resolve AIDP_ARTIFACTS_ROOT\n' >&2
        return 2; }
    fi
    if [ -z "$ws_root" ]; then
      ws_root="${_proj}/.claude/workflow-state"
    fi
  fi

  if [ -z "$run_id" ] || [ -z "$verify_status" ] || [ -z "$review_blocking" ]; then
    printf 'promote-latest-green: ERROR: --run-id, --verify-status, and --review-blocking are required\n' >&2
    usage >&2
    return 2
  fi

  # Boundary: parse run-id through the canonical parser (single source of truth).
  if ! run_id="$(parse_run_id "$run_id")"; then
    return 2
  fi

  # Boundary: parse verify-status and review-blocking.
  if ! verify_status="$(parse_verify_status "$verify_status")"; then
    return 2
  fi
  if ! review_blocking="$(parse_review_blocking "$review_blocking")"; then
    return 2
  fi

  # Core decision.
  if ! should_promote "$verify_status" "$review_blocking"; then
    style::warn "promote-latest-green skipped (verify=${verify_status} blocking=${review_blocking})" >&2
    return 0
  fi

  # Shell: refuse to point at a missing target (no dangling symlinks).
  local target_dir="$docs_root/runs/$run_id"
  if [ ! -d "$target_dir" ]; then
    printf 'promote-latest-green: ERROR: target run dir not found: %s\n' "$target_dir" >&2
    return 3
  fi

  atomic_update_green_symlink "$run_id" "$docs_root" || return $?
  atomic_update_green_text   "$run_id" "$docs_root" || return $?
  atomic_update_active_green "$run_id" "$ws_root"   || return $?

  style::step "latest-green promoted to ${run_id}"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
