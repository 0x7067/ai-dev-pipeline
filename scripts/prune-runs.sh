#!/usr/bin/env bash
# prune-runs.sh — retention policy for docs/runs/<id>/ directories.
#
# Layer: SHELL (filesystem mutation). The "which ids to delete" decision
# is computable as a pure function of (entries, mtimes, N, protected_set);
# we keep it inline for shell brevity but document the inputs explicitly
# so the policy is auditable.
#
# Policy:
#   - Keep the RUN_RETENTION (default 10) newest entries by mtime.
#   - Never delete a directory whose name appears in the protected set:
#       basename(readlink docs/latest), cat docs/latest.txt,
#       cat .claude/workflow-state/active.
#   - In CI (CI=true), no-op: CI artifact retention is the CI provider's
#     concern and we want green logs to be reproducible.
#
# Every deletion is announced on stderr; no surprise rm.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

RETENTION="${RUN_RETENTION:-10}"
RUNS_ROOT="${RUNS_ROOT:-docs/runs}"

if [ "${CI:-false}" = "true" ]; then
  echo "prune-runs: CI=true; skipping prune"
  exit 0
fi

if [ ! -d "$RUNS_ROOT" ]; then
  exit 0
fi

case "$RETENTION" in
  ''|*[!0-9]*)
    echo "prune-runs: ERROR: RUN_RETENTION must be a non-negative integer (got '$RETENTION')" >&2
    exit 2
    ;;
esac

# Build protected set.
protected=()
if [ -L "docs/latest" ]; then
  t=$(readlink "docs/latest" 2>/dev/null || true)
  [ -n "$t" ] && protected+=("$(basename "$t")")
fi
if [ -f "docs/latest.txt" ]; then
  v=$(head -n1 "docs/latest.txt" 2>/dev/null | tr -d '[:space:]')
  [ -n "$v" ] && protected+=("$v")
fi
if [ -f ".claude/workflow-state/active" ]; then
  v=$(head -n1 ".claude/workflow-state/active" 2>/dev/null | tr -d '[:space:]')
  [ -n "$v" ] && protected+=("$v")
fi

is_protected() {
  local needle="$1"
  [ -z "$needle" ] && return 0   # never delete an empty-named candidate
  # Empty array guard: ${arr[@]:-} expands to one empty element on bash 3.2,
  # which would falsely match a non-empty needle to nothing — handle the
  # zero-length case explicitly.
  if [ "${#protected[@]}" -eq 0 ]; then
    return 1
  fi
  local p
  for p in "${protected[@]}"; do
    [ "$p" = "$needle" ] && return 0
  done
  return 1
}

# Collect candidates, newest first. Only entries whose names parse as
# valid run-ids participate — anything else is left alone (foreign
# directories should never be silently deleted by retention).
stat_mtime() {
  # Portable mtime: BSD uses '-f %m', GNU uses '-c %Y'. Two-call dispatch
  # avoids unquoted-variable word-split footguns observed on macOS bash 3.2
  # where '$fmt' splits into multiple args and stat re-interprets later
  # tokens as path arguments.
  if stat -f %m / >/dev/null 2>&1; then
    stat -f '%m' "$1" 2>/dev/null
  else
    stat -c '%Y' "$1" 2>/dev/null
  fi
}

collect_runs_newest_first() {
  # Emit "<mtime>\t<path>" lines for every parseable run-id directory,
  # newest first. Tab separator keeps awk/sort robust against paths
  # containing spaces (defensive — the parser already forbids them).
  find "$RUNS_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null \
    | while IFS= read -r -d '' dir; do
        name=$(basename "$dir")
        if parse_run_id "$name" >/dev/null 2>&1; then
          local m
          m=$(stat_mtime "$dir")
          [ -n "$m" ] && printf '%s\t%s\n' "$m" "$dir"
        fi
      done \
    | sort -rn -k1,1
}

# Keep the first $RETENTION entries; delete the rest, skipping protected.
i=0
deleted=0
while IFS=$'\t' read -r mtime path; do
  [ -z "${path:-}" ] && continue
  name=$(basename "$path")
  i=$((i + 1))
  if [ "$i" -le "$RETENTION" ]; then
    continue
  fi
  if is_protected "$name"; then
    echo "prune-runs: keeping protected $name (active/latest)"
    continue
  fi
  echo "prune-runs: removing $path" >&2
  rm -rf -- "$path"
  deleted=$((deleted + 1))
done < <(collect_runs_newest_first)

echo "prune-runs: kept up to $RETENTION newest, removed $deleted"
