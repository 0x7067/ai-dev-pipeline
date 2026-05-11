#!/usr/bin/env bash
# render-end-of-run.sh — render the end-of-run summary block.
#
# Layer: SHELL. Pure presentation. Reads:
#   - ${RUN_DIR}/phase_timings.json  via scripts/parse-phase-timings.sh (BOUNDARY)
#   - ${RUN_DIR}/decisions.jsonl     line-oriented; consumes pre-typed records
#   - ${RUN_DIR}/.failure-summary    optional; fail-closed if absent (no preview)
#
# Writes a single block to stdout. Order (per AC4):
#   ─ Run summary ─
#   RUN_ID / RUN_DIR
#   (optional) failures: <one-line> + last 20 lines of log (hard cap)
#   (optional) timings:  plan 3s · verify 68s · ...
#   (optional) decisions: plan: <verb> · release: <verb>
#   Artifacts: ...
#   ─
#
# Hyperlink artifact paths via style::hyperlink (no-op when not on a TTY).
# When stdout is piped/redirected, style::strip_ansi MUST be applied by the
# caller; this script does NOT auto-strip — callers know the destination.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/lib/style.sh
source "${SCRIPT_DIR}/lib/style.sh"

FAILURE_PREVIEW_LINES=20

usage() {
  cat <<'EOF'
render-end-of-run.sh — render end-of-run summary block.

Usage:
  render-end-of-run.sh --run-dir <dir> [--run-id <id>]

Reads (all optional except --run-dir):
  ${RUN_DIR}/phase_timings.json   (timing strip)
  ${RUN_DIR}/decisions.jsonl      (decision trail)
  ${RUN_DIR}/.failure-summary     (failure block; optional)
EOF
}

_format_seconds() {
  local s="$1"
  if [ "$s" -ge 60 ]; then
    printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
  else
    printf '%ds' "$s"
  fi
}

# _read_phase_timings <path> — emits "name1\tseconds1\tstatus1\n..." on stdout.
# Routes through the boundary parser. Silent (no output) on absent/malformed.
_read_phase_timings() {
  local path="$1"
  [ -f "$path" ] || return 0
  local kv
  kv="$(bash "${SCRIPT_DIR}/parse-phase-timings.sh" "$path" 2>/dev/null)" || return 0
  local count
  count="$(printf '%s\n' "$kv" | sed -n 's/^phase_count=//p' | head -n1)"
  [ -n "$count" ] || return 0
  local i name secs status
  for ((i=1; i<=count; i++)); do
    name="$(printf '%s\n' "$kv" | sed -n "s/^phase_${i}_name=//p" | head -n1)"
    secs="$(printf '%s\n' "$kv" | sed -n "s/^phase_${i}_seconds=//p" | head -n1)"
    status="$(printf '%s\n' "$kv" | sed -n "s/^phase_${i}_status=//p" | head -n1)"
    printf '%s\t%s\t%s\n' "$name" "$secs" "$status"
  done
}

# _read_decisions <path> — emits "gate=verb" pairs, last record per gate wins.
_read_decisions() {
  local path="$1"
  [ -f "$path" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then return 0; fi
  jq -r 'select(.gate and .verb) | "\(.gate)=\(.verb)"' "$path" 2>/dev/null \
    | awk -F= '{ last[$1]=$2 } END { for (g in last) printf "%s=%s\n", g, last[g] }' \
    | sort
}

main() {
  local run_dir="" run_id="${RUN_ID:-}"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help|-h) usage; return 0 ;;
      --run-dir) run_dir="${2-}"; shift 2 ;;
      --run-id)  run_id="${2-}"; shift 2 ;;
      *) printf 'render-end-of-run: ERROR: unknown arg %q\n' "$1" >&2; return 2 ;;
    esac
  done
  if [ -z "$run_dir" ]; then
    printf 'render-end-of-run: ERROR: --run-dir is required\n' >&2
    return 2
  fi

  local abs_run_dir
  abs_run_dir="$(cd "$run_dir" 2>/dev/null && pwd -P)" || abs_run_dir="$run_dir"

  printf '─ Run summary ─────────────────────────────────────────\n'
  printf 'RUN_ID: %s\n' "${run_id:-(unset)}"
  printf 'RUN_DIR: %s\n' "$abs_run_dir"

  # ---- failures (above timing strip and artifacts; AC5) -------------------
  local failure_file="$run_dir/.failure-summary"
  if [ -s "$failure_file" ]; then
    printf 'failures:\n'
    # First line: failing phase/gate citation (free-form by writer).
    local first_line
    first_line="$(head -n1 "$failure_file")"
    printf '  %s\n' "$first_line"
    # If the writer recorded a log path on a `log=<path>` line, preview it.
    local log_path
    log_path="$(sed -n 's/^log=//p' "$failure_file" | head -n1)"
    if [ -n "$log_path" ] && [ -s "$log_path" ]; then
      local link
      link="$(style::hyperlink "file://$log_path" "$log_path")"
      printf '  log: %s (last %d lines)\n' "$link" "$FAILURE_PREVIEW_LINES"
      tail -n "$FAILURE_PREVIEW_LINES" "$log_path" | sed 's/^/    /'
    fi
  fi

  # ---- timing strip --------------------------------------------------------
  local phase_file="$run_dir/phase_timings.json"
  if [ -f "$phase_file" ]; then
    local strip="" name secs status fmt
    while IFS=$'\t' read -r name secs status; do
      [ -n "$name" ] || continue
      fmt="$(_format_seconds "$secs")"
      if [ "$status" = "fail" ]; then
        fmt="${fmt}!"
      fi
      if [ -z "$strip" ]; then
        strip="${name} ${fmt}"
      else
        strip="${strip} · ${name} ${fmt}"
      fi
    done < <(_read_phase_timings "$phase_file")
    if [ -n "$strip" ]; then
      printf 'timings: %s\n' "$strip"
    fi
  fi

  # ---- decision trail ------------------------------------------------------
  local dec_file="$run_dir/decisions.jsonl"
  if [ -f "$dec_file" ]; then
    local trail="" pair
    while IFS= read -r pair; do
      [ -n "$pair" ] || continue
      if [ -z "$trail" ]; then
        trail="${pair/=/: }"
      else
        trail="${trail} · ${pair/=/: }"
      fi
    done < <(_read_decisions "$dec_file")
    if [ -n "$trail" ]; then
      printf 'decisions: %s\n' "$trail"
    fi
  fi

  # ---- artifacts -----------------------------------------------------------
  printf 'Artifacts:\n'
  local pair label rel n abs link
  for pair in \
    "plan:current-plan.md" \
    "test-report:test-report.md" \
    "test-results:test-results.json" \
    "review-report:review-report.md" \
    "verify-report:verify-report.md" \
    "refactor:refactor-report.md" \
    "audit:audit-report.md"; do
    label="${pair%%:*}"; rel="${pair#*:}"
    abs="${abs_run_dir}/${rel}"
    if [ -s "$abs" ]; then
      n=$(wc -l < "$abs" | tr -d ' ')
      link="$(style::hyperlink "file://$abs" "$abs")"
      printf '  ✓ %-13s %s (%s lines)\n' "$label" "$link" "$n"
    fi
  done
  for dir in specs research adrs; do
    abs="${abs_run_dir}/${dir}"
    if [ -d "$abs" ]; then
      n=$(find "$abs" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')
      if [ "$n" -gt 0 ]; then
        link="$(style::hyperlink "file://$abs" "$abs/")"
        printf '  ✓ %-13s %s (%s file(s))\n' "$dir" "$link" "$n"
      fi
    fi
  done
  printf '───────────────────────────────────────────────────────\n'
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
