#!/usr/bin/env bash
# write-manifest.sh — emit ${RUN_DIR}/manifest.json for the current run.
#
# Layer: SHELL. Per .claude/rules/architecture-fcis.md this script handles
# all I/O (filesystem walk, sha256, git, clock) and delegates string
# composition to scripts/lib/manifest-core.sh (CORE, pure).
#
# Usage:
#   RUN_ID=<id> RUN_DIR=docs/runs/<id> bash scripts/write-manifest.sh \
#     [--command <name>] [--mode <mode>] [--risk-tier <tier>] [--status <status>]
#
# Exit codes:
#   0 — manifest written
#   1 — internal error (missing inputs, hashing tool absent, write failure)
#   2 — RUN_ID/RUN_DIR rejected by parser
#
# Strictly additive: makes no other filesystem changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/parse-run-id.sh
source "${SCRIPT_DIR}/parse-run-id.sh"
# shellcheck source=scripts/lib/manifest-core.sh
source "${SCRIPT_DIR}/lib/manifest-core.sh"

err() { printf 'write-manifest: ERROR: %s\n' "$*" >&2; }

# ---- sha256 detection (fail-closed) -----------------------------------------
detect_sha256_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    printf 'shasum -a 256'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256sum'
    return 0
  fi
  return 1
}

sha256_of_file() {
  local f="$1"
  local out
  if command -v shasum >/dev/null 2>&1; then
    out=$(shasum -a 256 -- "$f") || return 1
  elif command -v sha256sum >/dev/null 2>&1; then
    out=$(sha256sum -- "$f") || return 1
  else
    return 1
  fi
  # First whitespace-separated token is the digest.
  printf '%s' "${out%% *}"
}

bytes_of_file() {
  local f="$1"
  # Try BSD stat (-f%z) then GNU stat (-c%s); fall back to wc -c.
  local n
  n=$(stat -f%z -- "$f" 2>/dev/null) && { printf '%s' "$n"; return 0; }
  n=$(stat -c%s -- "$f" 2>/dev/null) && { printf '%s' "$n"; return 0; }
  n=$(wc -c < "$f" 2>/dev/null | tr -d ' ') && { printf '%s' "$n"; return 0; }
  return 1
}

# ---- git capture (best-effort; absent => empty strings) ---------------------
git_head() {
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    git rev-parse HEAD 2>/dev/null
  fi
}
git_branch() {
  if command -v git >/dev/null 2>&1; then
    git rev-parse --abbrev-ref HEAD 2>/dev/null || true
  fi
}
git_dirty() {
  if command -v git >/dev/null 2>&1 && git status --porcelain >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      printf 'true'
    else
      printf 'false'
    fi
  else
    printf 'false'
  fi
}

# ---- artifact enumeration ---------------------------------------------------
# Walks RUN_DIR, emits one record per regular file as a NUL-delimited triple:
#   <relpath>\0<sha256>\0<bytes>\0
# NUL is the only byte POSIX guarantees cannot appear in a filename. TAB and
# newline are legal in filenames; using them as delimiters is unsafe (see
# review BLOCKING-2). Filenames containing literal NUL are not representable
# (the kernel rejects them at open(2)) but find should never produce them;
# we still defensively reject any path whose bash-side representation
# contains an embedded NUL by virtue of read -d '' framing.
enumerate_artifacts() {
  local run_dir="$1"
  local f rel sha n
  while IFS= read -r -d '' f; do
    rel="${f#"$run_dir"/}"
    if [ "$rel" = "manifest.json" ]; then
      continue
    fi
    # Skip symlinks: shell-side defence in depth (parser also rejects escape).
    if [ -L "$f" ]; then
      continue
    fi
    [ -f "$f" ] || continue
    # Reject filenames containing TAB, NL, CR. These are POSIX-legal but
    # the v1 manifest contract refuses them: the parser's JSON escape
    # decoding is asymmetric (escape sequences not decoded prior to safety
    # checks), so a round-tripped value cannot be byte-equal to the input.
    # Fail-closed (review BLOCKING-2): refuse rather than emit a manifest
    # the parser would not match against the source.
    case "$rel" in
      *$'\t'*|*$'\n'*|*$'\r'*)
        err "artifact filename contains TAB/NL/CR (refused): $rel"
        return 1
        ;;
    esac
    sha=$(sha256_of_file "$f") || { err "sha256 failed for $f"; return 1; }
    n=$(bytes_of_file "$f") || { err "stat failed for $f"; return 1; }
    # NUL-delimited triple. Each field terminated by NUL; record is three NULs.
    printf '%s\0%s\0%s\0' "$rel" "$sha" "$n"
  done < <(find "$run_dir" -type f -print0 2>/dev/null)
}

# ---- artifact-kind heuristic (advisory only) --------------------------------
infer_kind() {
  local rel="$1"
  case "$rel" in
    current-plan.md)        printf 'plan' ;;
    review-report.md)       printf 'review' ;;
    verify-report.md)       printf 'verify' ;;
    test-report.md)         printf 'test' ;;
    refactor-report.md)     printf 'refactor' ;;
    audit-report.md)        printf 'audit' ;;
    adrs/*.md)              printf 'adr' ;;
    research/*.md)          printf 'research' ;;
    specs/*.md)             printf 'spec' ;;
    *)                      printf 'other' ;;
  esac
}

main() {
  local opt_command="ship" opt_mode="" opt_risk="" opt_status="ok"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --command)   opt_command="$2"; shift 2 ;;
      --mode)      opt_mode="$2"; shift 2 ;;
      --risk-tier) opt_risk="$2"; shift 2 ;;
      --status)    opt_status="$2"; shift 2 ;;
      *) err "unknown arg: $1"; return 1 ;;
    esac
  done

  : "${RUN_ID:?RUN_ID not set}"
  : "${RUN_DIR:?RUN_DIR not set}"

  # Boundary check: RUN_ID via the canonical parser.
  if ! parse_run_id "$RUN_ID" >/dev/null; then
    err "RUN_ID failed parser self-check: $RUN_ID"
    return 2
  fi

  if [ ! -d "$RUN_DIR" ]; then
    err "RUN_DIR does not exist: $RUN_DIR"
    return 1
  fi

  if ! detect_sha256_cmd >/dev/null; then
    err "no sha256 tool available (need shasum or sha256sum)"
    return 1
  fi

  # Build entries.
  local entries_args=() rel sha bytes kind entry
  local tmp_list tmp_idx
  tmp_list=$(mktemp -t manifest-list.XXXXXX) || { err "mktemp failed"; return 1; }
  tmp_idx=$(mktemp -t manifest-idx.XXXXXX)   || { err "mktemp failed"; rm -f "$tmp_list"; return 1; }
  # Single trap covers all scratch files for every exit path (combined per
  # review advisory: avoid double-trap overwrite).
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_list' '$tmp_idx'" EXIT

  if ! enumerate_artifacts "$RUN_DIR" > "$tmp_list"; then
    err "artifact enumeration failed"
    return 1
  fi

  # Read NUL-delimited triples (rel, sha, bytes) into parallel arrays.
  # NUL framing is filename-safe (TAB, NL, CR all legal in POSIX paths).
  local rels=() shas=() byts=()
  local field_idx=0
  while IFS= read -r -d '' f; do
    case "$field_idx" in
      0) rels+=("$f");  field_idx=1 ;;
      1) shas+=("$f");  field_idx=2 ;;
      2) byts+=("$f");  field_idx=0 ;;
    esac
  done < "$tmp_list"
  if [ "$field_idx" -ne 0 ]; then
    err "artifact enumeration produced truncated record"
    return 1
  fi

  # Sort the parallel arrays by relpath, deterministically. We use a
  # scratch tmp file with index|rel rows piped through sort -- the index
  # is what we care about; rel never contains NUL.
  local n_entries=${#rels[@]} sort_idx
  if [ "$n_entries" -gt 0 ]; then
    local k rel_hex
    : > "$tmp_idx"
    for (( k=0; k<n_entries; k++ )); do
      # Sort by a hex encoding of the relpath bytes. NL/TAB are rejected
      # upstream, but using hex keeps the sort key safe regardless.
      rel_hex=$(printf '%s' "${rels[$k]}" | LC_ALL=C od -An -tx1 | tr -d ' \n')
      printf '%s %d\n' "$rel_hex" "$k" >> "$tmp_idx"
    done
    sort_idx=$(LC_ALL=C sort "$tmp_idx" | awk '{print $2}')
  else
    sort_idx=""
  fi

  local idx
  for idx in $sort_idx; do
    rel="${rels[$idx]}"
    sha="${shas[$idx]}"
    bytes="${byts[$idx]}"
    [ -n "$rel" ] || continue
    kind=$(infer_kind "$rel")
    if ! entry=$(manifest_build_entry "$kind" "$rel" "$sha" "$bytes"); then
      err "core builder rejected entry for: $rel (bytes=$bytes)"
      return 1
    fi
    entries_args+=("$entry")
  done

  local entries_json
  entries_json=$(manifest_build_entries_array "${entries_args[@]:-}")

  # Clock & git capture.
  local now head branch dirty
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  head=$(git_head)
  branch=$(git_branch)
  dirty=$(git_dirty)

  local body
  body=$(manifest_build \
    "$RUN_ID" \
    "$now" "$now" \
    "$opt_command" "$opt_mode" "$opt_risk" "$opt_status" \
    "$head" "$branch" "$dirty" \
    "$entries_json")

  # Atomic write: tmp + rename, per-process suffix mirrors mint-run-id.sh.
  local target="$RUN_DIR/manifest.json"
  local suffix="$$.${RANDOM:-0}"
  local tmp="$RUN_DIR/manifest.json.tmp.$suffix"
  printf '%s\n' "$body" > "$tmp" || { err "tmp write failed"; return 1; }
  mv "$tmp" "$target" || { err "atomic rename failed"; rm -f "$tmp"; return 1; }
  printf '%s\n' "$target"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
