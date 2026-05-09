#!/usr/bin/env bash
# queue-pending-approval.sh — atomic writer for ${RUN_DIR}/.pending-approval.json.
#
# Layer: SHELL. Writes the pending-approval marker atomically via
# tempfile + rename. Per HITL plan invariant 9, a reader either sees
# a complete record or no file. Companion parser:
# scripts/parse-pending-approval.sh.
#
# Usage:
#   bash scripts/queue-pending-approval.sh \
#     --run-dir <path> \
#     --run-id <id> \
#     --gate <plan|release|refactor-plan> \
#     [--deadline-iso <iso8601>] \
#     [--plan-hash <hex>] \
#     --created-at <iso8601-utc>
#
# `--created-at` is REQUIRED (no ambient clock — purity gate).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

run_dir="" run_id="" gate="" deadline_iso="" plan_hash="" created_at=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run-dir)      run_dir="${2-}"; shift 2 ;;
    --run-id)       run_id="${2-}"; shift 2 ;;
    --gate)         gate="${2-}"; shift 2 ;;
    --deadline-iso) deadline_iso="${2-}"; shift 2 ;;
    --plan-hash)    plan_hash="${2-}"; shift 2 ;;
    --created-at)   created_at="${2-}"; shift 2 ;;
    *)
      printf 'queue-pending-approval: unknown arg %q\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$run_dir" ] || [ -z "$run_id" ] || [ -z "$gate" ] || [ -z "$created_at" ]; then
  printf 'queue-pending-approval: --run-dir, --run-id, --gate, --created-at required\n' >&2
  exit 2
fi
if [ ! -d "$run_dir" ]; then
  printf 'queue-pending-approval: run-dir not a directory: %s\n' "$run_dir" >&2
  exit 2
fi
parse_run_id "$run_id" >/dev/null || exit 2
case "$gate" in
  plan|release|refactor-plan) : ;;
  *) printf 'queue-pending-approval: bad gate %q\n' "$gate" >&2; exit 2 ;;
esac
# Reject control chars in any field.
for f in "$deadline_iso" "$plan_hash" "$created_at"; do
  case "$f" in
    *$'\n'*|*$'\r'*|*$'\x1b'*|*\"*|*\\*)
      printf 'queue-pending-approval: forbidden char in field\n' >&2
      exit 2
      ;;
  esac
done

target="${run_dir%/}/.pending-approval.json"
tmp="${target}.tmp.$$.${RANDOM:-0}"
printf '{"run_id":"%s","gate":"%s","deadline_iso":"%s","plan_hash":"%s","created_at":"%s"}\n' \
  "$run_id" "$gate" "$deadline_iso" "$plan_hash" "$created_at" \
  >"$tmp" || { printf 'queue-pending-approval: write failed\n' >&2; exit 1; }
mv -f "$tmp" "$target" || { rm -f "$tmp"; printf 'queue-pending-approval: rename failed\n' >&2; exit 1; }
printf '%s\n' "$target"
