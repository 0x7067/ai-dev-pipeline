#!/usr/bin/env bash
# mint-run-id.sh — generate a fresh, parseable RunId.
#
# Layer split per .claude/rules/architecture-fcis.md:
#   CORE  : compose_run_id(timestamp, sha, disambiguator) — pure string fn.
#   SHELL : reads system clock, git, /dev/urandom; optionally writes
#           docs/latest, docs/latest.txt, .claude/workflow-state/active.
#
# Self-checks the minted id through scripts/parse-run-id.sh before
# emitting it, so a regression in either side fails closed.
#
# Output (stdout): the canonical run-id, one line, no trailing whitespace.
#
# Flags:
#   --write-pointers   also create/update docs/latest, docs/latest.txt,
#                      and .claude/workflow-state/active atomically.
#   --run-dir <path>   override docs/runs root (default: docs/runs).
#                      Used by tests; production callers should not set it.
#
# Env (read-only):
#   GITHUB_RUN_ID      if set and RUN_ID is unset, the id is wrapped as
#                      <ts>-<sha>-<hex2(GITHUB_RUN_ID mod 256)> so the
#                      format invariant holds end-to-end (CI translation).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"

# ---- core (pure) -------------------------------------------------------------

# compose_run_id <ts> <sha6> [<disamb2>]
#   ts     : UTC timestamp YYYYMMDDTHHMMSSZ or YYYYMMDDTHHMMSS
#   sha6   : 6 lowercase hex chars
#   disamb : optional 2 lowercase hex chars
compose_run_id() {
  local ts="$1" sha="$2" disamb="${3-}"
  if [ -n "$disamb" ]; then
    printf '%s-%s-%s' "$ts" "$sha" "$disamb"
  else
    printf '%s-%s' "$ts" "$sha"
  fi
}

# ---- shell (impure) ----------------------------------------------------------

now_utc_compact() {
  # Deliberately drops Z to keep the most-common shape at 22 chars.
  # parse-run-id.sh accepts Z-suffix too if a future caller wants it.
  date -u +%Y%m%dT%H%M%S
}

short_sha_or_random() {
  local s
  if command -v git >/dev/null 2>&1 && git rev-parse --short=6 HEAD >/dev/null 2>&1; then
    s=$(git rev-parse --short=6 HEAD 2>/dev/null | tr 'A-Z' 'a-z')
    if [ "${#s}" -eq 6 ]; then
      printf '%s' "$s"
      return 0
    fi
  fi
  # Fallback: 6 random hex from /dev/urandom.
  LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 6
}

random_hex2() {
  LC_ALL=C tr -dc 'a-f0-9' </dev/urandom 2>/dev/null | head -c 2
}

ci_disambiguator() {
  # Wrap a CI numeric id into 2 hex chars (mod 256). Stable enough for
  # disambiguation across same-second concurrent CI starts.
  local v="${GITHUB_RUN_ID-}"
  [ -z "$v" ] && return 0
  case "$v" in
    *[!0-9]*) return 0 ;;  # non-numeric — skip rather than corrupt the id
  esac
  printf '%02x' "$(( v % 256 ))"
}

atomic_update_latest() {
  # update docs/latest -> docs/runs/<id> (symlink) and write docs/latest.txt
  # both updates are atomic via rename (POSIX ln -sfn + mv .tmp).
  # Per-process tmp suffix avoids two concurrent mints racing on a shared
  # tmp filename (one process's mv consuming another's tmp).
  local id="$1" runs_root="$2"
  local docs_root suffix
  docs_root="$(dirname "$runs_root")"
  suffix="$$.${RANDOM:-0}"
  mkdir -p "$runs_root/$id"
  # Symlink: relative target so worktrees move correctly.
  local rel_target="runs/$id"
  ( cd "$docs_root" && ln -sfn "$rel_target" "latest.tmp.$suffix" && mv "latest.tmp.$suffix" "latest" )
  # Text fallback: atomic via tmp+rename.
  printf '%s\n' "$id" > "$docs_root/latest.txt.tmp.$suffix"
  mv "$docs_root/latest.txt.tmp.$suffix" "$docs_root/latest.txt"
}

atomic_update_active_workflow_state() {
  local id="$1"
  local dir=".claude/workflow-state"
  local suffix="$$.${RANDOM:-0}"
  mkdir -p "$dir"
  printf '%s\n' "$id" > "$dir/active.tmp.$suffix"
  mv "$dir/active.tmp.$suffix" "$dir/active"
}

# ---- entrypoint --------------------------------------------------------------

main() {
  local write_pointers=0
  local runs_root="docs/runs"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --write-pointers) write_pointers=1; shift ;;
      --run-dir) runs_root="$2"; shift 2 ;;
      *) printf 'mint-run-id: ERROR: unknown arg %q\n' "$1" >&2; exit 2 ;;
    esac
  done

  local ts sha disamb id
  ts=$(now_utc_compact)
  sha=$(short_sha_or_random)
  if [ "${#sha}" -ne 6 ]; then
    printf 'mint-run-id: ERROR: could not obtain 6-hex sha\n' >&2
    exit 1
  fi
  # Prefer CI disambiguator if present; otherwise random when we'd otherwise
  # collide on a same-second multi-mint (cheap insurance, costs nothing).
  disamb=$(ci_disambiguator)
  if [ -z "$disamb" ]; then
    disamb=$(random_hex2)
  fi
  id=$(compose_run_id "$ts" "$sha" "$disamb")

  # Self-check at the boundary before any side effect.
  if ! parse_run_id "$id" >/dev/null; then
    printf 'mint-run-id: ERROR: minted id failed parser self-check: %q\n' "$id" >&2
    exit 1
  fi

  if [ "$write_pointers" = "1" ]; then
    mkdir -p "$runs_root/$id"
    atomic_update_latest "$id" "$runs_root"
    atomic_update_active_workflow_state "$id"
  fi

  printf '%s\n' "$id"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
