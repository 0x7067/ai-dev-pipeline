#!/usr/bin/env bash
# promote-core.sh — pure decision predicate for latest-green promotion.
#
# Layer: CORE (pure). No I/O, no ambient state. Sourced by
# scripts/promote-latest-green.sh.
#
# Contract:
#   should_promote <verify_status> <review_blocking>
#     - returns 0 (true)  iff verify_status == "go" AND review_blocking == "0"
#     - returns 1 (false) otherwise
#   Inputs are assumed already parsed at the boundary (allowlist for
#   verify_status, non-negative integer for review_blocking). The function
#   does not re-parse: it only decides.

should_promote() {
  local verify_status="${1-}"
  local review_blocking="${2-}"
  if [ "$verify_status" = "go" ] && [ "$review_blocking" = "0" ]; then
    return 0
  fi
  return 1
}
