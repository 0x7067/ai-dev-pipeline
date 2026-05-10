#!/usr/bin/env bash
# resume-core.sh — pure dispatch for `release.sh` resume.
#
# FC/IS placement: CORE. No I/O, no ambient state, no subprocess calls.
# Inputs are explicit parameters (already-parsed phase + answer). Output is a
# single action token on stdout.
#
# Public API:
#
#   release_resume_decide <phase> <answer>
#       phase  ∈ {pending-version-confirm, phase-b-complete}
#       answer ∈ {approve, reject, "", pick:<X.Y.Z>}
#       -> prints exactly one action token:
#            run-phase-b              # version-confirm + approve|pick
#            push                     # phase-b-complete + approve
#            reject-pre-mutation      # version-confirm + reject|""
#            reject-post-mutation     # phase-b-complete + reject|""
#            error:ambiguous-answer   # answer not legal for the phase
#            error:unknown-phase      # phase not in the closed set
#       Returns 0 even on error tokens — the caller branches on the token.
#       This keeps the function total and easy to test.
#
# Invariants:
#   - I-phase-source-of-truth: the chosen action depends ONLY on the two
#     parameters. No env vars read.
#   - I-no-retag: `push` is the only action emitted for phase-b-complete +
#     approve. The caller MUST NOT re-run mutations on this branch.

# shellcheck shell=bash

if [[ -n "${_RELEASE_RESUME_CORE_LOADED:-}" ]]; then return 0; fi
_RELEASE_RESUME_CORE_LOADED=1

release_resume_decide() {
  local phase="${1:-}" answer="${2:-}"
  case "$phase" in
    pending-version-confirm)
      case "$answer" in
        approve)        printf 'run-phase-b\n' ;;
        pick:*)         printf 'run-phase-b\n' ;;
        reject|"")      printf 'reject-pre-mutation\n' ;;
        *)              printf 'error:ambiguous-answer\n' ;;
      esac
      ;;
    phase-b-complete)
      case "$answer" in
        approve)        printf 'push\n' ;;
        reject|"")      printf 'reject-post-mutation\n' ;;
        *)              printf 'error:ambiguous-answer\n' ;;
      esac
      ;;
    *)
      printf 'error:unknown-phase\n'
      ;;
  esac
  return 0
}
