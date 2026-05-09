#!/usr/bin/env bash
# hitl-core.sh — pure (FC) helpers for the HITL pipeline.
#
# Layer: CORE per .claude/rules/architecture-fcis.md. No I/O, no clock,
# no network. Time-like inputs (`now`, `deadline`) are explicit
# parameters. The shell layer composes these results into banners,
# halts, and audit-log writes.

# Guard against double-source.
if [ -n "${_HITL_CORE_LOADED:-}" ]; then return 0 2>/dev/null || true; fi
_HITL_CORE_LOADED=1

# risk_rationale_format <tier> <reason>
#   Returns the canonical one-line banner phrase: "risk=<tier> because <reason>".
#   Pure: no styling, no ANSI. Shell renders the banner via style.sh.
risk_rationale_format() {
  local tier="${1-}" reason="${2-}"
  case "$tier" in
    low|medium|high|unknown) : ;;
    *) printf 'risk_rationale_format: invalid tier %q\n' "$tier" >&2; return 2 ;;
  esac
  if [ -z "$reason" ]; then reason="(unspecified)"; fi
  # Reject control chars / ANSI in reason — it must be a single line.
  case "$reason" in
    *$'\n'*|*$'\r'*|*$'\x1b'*)
      printf 'risk_rationale_format: forbidden control char in reason\n' >&2
      return 2
      ;;
  esac
  printf 'risk=%s because %s\n' "$tier" "$reason"
}

# policy_apply <mode> <risk> <blocking> <verifier> <smoke>
#   Pure decision function for the release gate.
#   Inputs are TYPED (caller has already parsed them; no raw strings).
#   Echoes one of: "auto-approve" | "prompt" | "reject".
#   Invariant: any unknown/malformed input MUST yield "prompt" or "reject"
#   — never "auto-approve" (HITL plan invariant 1, fail-closed).
policy_apply() {
  local mode="${1-}" risk="${2-}" blocking="${3-}" verifier="${4-}" smoke="${5-}"
  # Validate enums; anything off → fail closed to "prompt".
  case "$mode"     in auto|strict) : ;; *) printf 'prompt\n'; return 0 ;; esac
  case "$risk"     in low|medium|high|unknown) : ;; *) printf 'prompt\n'; return 0 ;; esac
  case "$verifier" in go|no-go|fail) : ;; *) printf 'prompt\n'; return 0 ;; esac
  case "$smoke"    in passed|failed) : ;; *) printf 'prompt\n'; return 0 ;; esac
  if ! [[ "$blocking" =~ ^[0-9]+$ ]]; then
    printf 'prompt\n'; return 0
  fi
  if [ "$mode" = "auto" ] \
     && [ "$risk" = "low" ] \
     && [ "$blocking" -eq 0 ] \
     && [ "$verifier" = "go" ] \
     && [ "$smoke" = "passed" ]; then
    printf 'auto-approve\n'
    return 0
  fi
  if [ "$verifier" = "no-go" ] || [ "$verifier" = "fail" ] || [ "$smoke" = "failed" ]; then
    # Primary decision (unchanged contract for existing callers).
    printf 'reject\n'
    # Audit hint on stderr — distinguishes verifier crash (`fail`) from
    # gates-failed (`no-go`) from a smoke regression. Callers that want
    # to record a rich rationale in decisions.jsonl can capture this on
    # the side; callers that only need the primary decision can ignore
    # stderr. This preserves audit signal without changing the
    # auto-approve safety contract (HITL plan invariant 1).
    local reason
    if [ "$verifier" = "fail" ]; then
      reason="verifier-crashed"
    elif [ "$verifier" = "no-go" ]; then
      reason="gates-failed"
    else
      reason="smoke-failed"
    fi
    printf 'reject-reason=%s\n' "$reason" >&2
    return 0
  fi
  printf 'prompt\n'
}

# refactor_scope_classify <file_count> <loc_delta> <files_threshold> <loc_threshold>
#   Returns "above" | "below" — pure scope classification used by /refactor.
refactor_scope_classify() {
  local files="${1-}" loc="${2-}" ft="${3-}" lt="${4-}"
  for x in "$files" "$loc" "$ft" "$lt"; do
    if ! [[ "$x" =~ ^[0-9]+$ ]]; then
      printf 'refactor_scope_classify: non-integer %q\n' "$x" >&2
      return 2
    fi
  done
  if [ "$files" -gt "$ft" ] || [ "$loc" -gt "$lt" ]; then
    printf 'above\n'
  else
    printf 'below\n'
  fi
}

# time_box_resolve <now_epoch> <deadline_epoch>
#   Pure timer evaluation.
#   Outputs key=value pairs:
#     expired=<true|false>
#     remaining=<seconds, signed>
#   Property (HITL plan invariant 5): for fixed deadline, expired is
#   monotonic in `now` — once true, stays true.
time_box_resolve() {
  local now="${1-}" deadline="${2-}"
  for x in "$now" "$deadline"; do
    if ! [[ "$x" =~ ^-?[0-9]+$ ]]; then
      printf 'time_box_resolve: non-integer %q\n' "$x" >&2
      return 2
    fi
  done
  local remaining=$((deadline - now))
  if [ "$now" -ge "$deadline" ]; then
    printf 'expired=true\nremaining=%d\n' "$remaining"
  else
    printf 'expired=false\nremaining=%d\n' "$remaining"
  fi
}
