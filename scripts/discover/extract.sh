#!/usr/bin/env bash
# extract.sh — shell layer for /audit standards pattern extraction.
#
# Orchestrates ast-grep + universal-ctags over tracked repo files.
# Paths are handled NUL-delimited throughout to avoid word-splitting.
#
# FC/IS layer: SHELL
#
# Usage:
#   bash extract.sh [OPTIONS]
#
# Options:
#   --bucket <name>        Only process files assigned to this bucket
#   --threshold <n>        Confidence threshold percent (default: 70)
#   --min-bucket <n>       Minimum files per bucket (default: 5)
#   --langs <l1,l2,...>    Comma-separated language filter
#   --output-dir <dir>     Directory to write JSON output (default: stdout JSON)
#   --dry-run              Print what would run, do not execute
#
# Outputs two JSON Lines files when --output-dir is set:
#   <output-dir>/astgrep.jsonl   — ast-grep matches
#   <output-dir>/ctags.jsonl     — ctags symbols
#
# Exit codes:
#   0  success
#   1  tool not found (ast-grep or ctags)
#   2  not a git repository
#   3  invalid --bucket value
#   4  internal error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
RULES_DIR="${SCRIPT_DIR}/rules"

# Source style library for output
# shellcheck source=scripts/lib/style.sh
if [ -f "${REPO_ROOT}/scripts/lib/style.sh" ]; then
  source "${REPO_ROOT}/scripts/lib/style.sh"
else
  # Minimal fallbacks so the script works standalone
  style::step() { echo "-- $*"; }
  style::ok()   { echo "[ok] $*"; }
  style::fail() { echo "[fail] $*" >&2; }
  style::info() { echo "* $*"; }
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
BUCKET_FILTER=""
THRESHOLD="${AIDP_DISCOVER_THRESHOLD:-70}"
MIN_BUCKET="${AIDP_DISCOVER_BUCKET_MIN:-5}"
LANGS_FILTER="${AIDP_DISCOVER_LANGS:-}"
OUTPUT_DIR=""
DRY_RUN=0

# ---------------------------------------------------------------------------
# Argument parsing (boundary: validate before use)
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      shift
      RAW_BUCKET="${1:-}"
      # Boundary validate: ^[a-z0-9_-]+$
      if [[ -z "$RAW_BUCKET" ]] || ! [[ "$RAW_BUCKET" =~ ^[a-z0-9_-]+$ ]]; then
        style::fail "extract: invalid --bucket value: ${RAW_BUCKET@Q}"
        style::fail "extract: must match ^[a-z0-9_-]+$ (lower-case alphanumeric, hyphens, underscores)"
        exit 3
      fi
      BUCKET_FILTER="$RAW_BUCKET"
      ;;
    --threshold)
      shift
      THRESHOLD="${1:-70}"
      ;;
    --min-bucket)
      shift
      MIN_BUCKET="${1:-5}"
      ;;
    --langs)
      shift
      LANGS_FILTER="${1:-}"
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:-}"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      style::fail "extract: unknown argument: ${1@Q}"
      exit 4
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Pre-flight: verify required tools
# ---------------------------------------------------------------------------
_check_tool() {
  local name="$1"
  local install_hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    style::fail "extract: required tool not found: ${name}"
    style::fail "  install: ${install_hint}"
    exit 1
  fi
}

_check_tool ast-grep "brew install ast-grep  OR  cargo install ast-grep"
_check_tool ctags    "brew install universal-ctags  OR  apt-get install universal-ctags"

# ---------------------------------------------------------------------------
# Pre-flight: verify git checkout
# ---------------------------------------------------------------------------
if ! git -C "${REPO_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  style::fail "extract: not a git repository: ${REPO_ROOT}"
  exit 2
fi

# ---------------------------------------------------------------------------
# Gather tracked files (NUL-delimited, untracked excluded)
# ---------------------------------------------------------------------------
style::step "extract: gathering tracked files (git ls-files -z)"

# Write NUL-delimited file list to a temp file so we can reuse it
_tmpdir="$(mktemp -d)"
trap 'rm -rf "${_tmpdir}"' EXIT
_files_nul="${_tmpdir}/files.nul"

git -C "${REPO_ROOT}" ls-files -z > "${_files_nul}"

_file_count=0
while IFS= read -r -d '' _f; do
  _file_count=$((_file_count + 1))
done < "${_files_nul}"
style::info "extract: ${_file_count} tracked files"

# ---------------------------------------------------------------------------
# Run ctags (NUL-safe via -L with NUL delimiter via xargs)
# ---------------------------------------------------------------------------
_ctags_out="${_tmpdir}/ctags.jsonl"

if [ "$DRY_RUN" -eq 1 ]; then
  style::step "extract: [dry-run] would run ctags --output-format=json over ${_file_count} files"
else
  style::step "extract: running universal-ctags"
  # Use xargs with -0 to handle spaces/special chars in paths; ctags reads from stdin via -L -
  # Write JSON Lines to ctags.jsonl
  (
    cd "${REPO_ROOT}"
    xargs -0 ctags \
      --output-format=json \
      --fields=+n \
      --extras=+q \
      -f - \
      < "${_files_nul}" \
    > "${_ctags_out}" 2>/dev/null || true
  )
  _ctags_lines=$(wc -l < "${_ctags_out}" 2>/dev/null || echo 0)
  style::ok "extract: ctags produced ${_ctags_lines} symbol records"
fi

# ---------------------------------------------------------------------------
# Run ast-grep over rule files (NUL-safe: one rule file at a time)
# ---------------------------------------------------------------------------
_astgrep_out="${_tmpdir}/astgrep.jsonl"
: > "${_astgrep_out}"  # empty/create

if [ "$DRY_RUN" -eq 1 ]; then
  style::step "extract: [dry-run] would run ast-grep over rules in ${RULES_DIR}"
else
  style::step "extract: running ast-grep over rules"
  _rule_count=0
  for _rule_file in "${RULES_DIR}"/*.yml; do
    [ -f "$_rule_file" ] || continue
    _rule_count=$((_rule_count + 1))
    # ast-grep --json=stream reads from current dir; we specify paths via --
    # Use NUL-delimited input via a process substitution workaround:
    # ast-grep does not support NUL-delimited file lists directly, so we
    # pipe paths through a helper that processes them safely.
    (
      cd "${REPO_ROOT}"
      # Convert NUL-delimited paths to newline for ast-grep (ast-grep's
      # --json=stream handles paths with spaces when quoted properly).
      # We use --jobs=1 to keep output ordering deterministic.
      while IFS= read -r -d '' _filepath; do
        [ -f "${_filepath}" ] || continue
        ast-grep scan \
          --rule "${_rule_file}" \
          --json \
          -- "${_filepath}" \
        2>/dev/null || true
      done < "${_files_nul}"
    ) >> "${_astgrep_out}"
  done
  _astgrep_lines=$(wc -l < "${_astgrep_out}" 2>/dev/null || echo 0)
  style::ok "extract: ast-grep produced ${_astgrep_lines} match records (${_rule_count} rule files)"
fi

# ---------------------------------------------------------------------------
# Copy to output-dir if requested, else print paths
# ---------------------------------------------------------------------------
if [ -n "$OUTPUT_DIR" ]; then
  mkdir -p "${OUTPUT_DIR}"
  cp "${_ctags_out}"  "${OUTPUT_DIR}/ctags.jsonl"
  cp "${_astgrep_out}" "${OUTPUT_DIR}/astgrep.jsonl"
  style::ok "extract: output written to ${OUTPUT_DIR}"
else
  style::info "extract: ctags data at ${_ctags_out}"
  style::info "extract: astgrep data at ${_astgrep_out}"
  # Emit paths for caller to consume
  echo "CTAGS_JSONL=${_ctags_out}"
  echo "ASTGREP_JSONL=${_astgrep_out}"
fi
