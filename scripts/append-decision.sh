#!/usr/bin/env bash
# append-decision.sh — atomic appender for ${RUN_DIR}/decisions.jsonl.
#
# Layer: SHELL. Wraps the pure decision_record_build (core) and writes
# the resulting line to disk. Writes are atomic at the line level via
# `flock` when available, falling back to O_APPEND-aware printf which
# is atomic for writes < PIPE_BUF (4 KiB on macOS/Linux) — every record
# encoded by decision_record_build fits.
#
# Usage:
#   bash scripts/append-decision.sh \
#     --run-dir <path> \
#     --ts <iso8601> \
#     --actor <user|auto|time-box> \
#     --gate <plan|release|refactor-plan> \
#     --verb <approve|edit|reject> \
#     --rationale <text> \
#     --plan-hash <hex>
#
# `--ts` is REQUIRED (no ambient clock — purity gate). Callers compose
# `now` at the orchestrator boundary, e.g. `date -u +%FT%TZ`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=lib/decisions-core.sh
source "${SCRIPT_DIR}/lib/decisions-core.sh"

run_dir="" ts="" actor="" gate="" verb="" rationale="" plan_hash=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)   run_dir="${2-}"; shift 2 ;;
    --ts)        ts="${2-}"; shift 2 ;;
    --actor)     actor="${2-}"; shift 2 ;;
    --gate)      gate="${2-}"; shift 2 ;;
    --verb)      verb="${2-}"; shift 2 ;;
    --rationale) rationale="${2-}"; shift 2 ;;
    --plan-hash) plan_hash="${2-}"; shift 2 ;;
    *)
      printf 'append-decision: unknown arg %q\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$run_dir" ]; then
  printf 'append-decision: --run-dir required\n' >&2
  exit 2
fi
if [ ! -d "$run_dir" ]; then
  printf 'append-decision: run-dir not a directory: %s\n' "$run_dir" >&2
  exit 2
fi

# Build the JSONL line via the pure core function.
line="$(decision_record_build "$ts" "$actor" "$gate" "$verb" "$rationale" "$plan_hash")" || exit 2

target="${run_dir%/}/decisions.jsonl"

# Atomic append: prefer flock, fall back to plain >>.
if command -v flock >/dev/null 2>&1; then
  exec 9>>"$target" || { printf 'append-decision: open failed\n' >&2; exit 1; }
  flock 9
  printf '%s\n' "$line" >&9
  exec 9>&-
else
  printf '%s\n' "$line" >>"$target"
fi
