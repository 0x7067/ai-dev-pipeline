#!/usr/bin/env bash
# /refactor-local pre-gate. Hybrid coverage check + rationale fallback.
#
# Simplified design (no per-format parsers): each supported coverage tool is
# invoked with its NATIVE threshold flag, and we trust the tool's exit code.
# The single exception is `go test -cover`, which prints `coverage: XX.X%`
# but lacks a built-in fail-under. For Go we extract the percentage with
# grep+awk and compare to threshold.
#
# Detection order (first hit wins):
#   1. pytest          (pytest --cov-fail-under=$threshold --cov=$target)
#   2. go test -cover  (parse `coverage: XX.X%` from output)
#   3. cargo llvm-cov  (--fail-under-lines $threshold)
#   4. cargo tarpaulin (--fail-under $threshold)
#   5. vitest          (--coverage.thresholds.lines=$threshold)
#   6. jest            (--coverageThreshold='{"global":{"lines":N}}')
#   7. c8              (--check-coverage --lines=$threshold)
#
# When no tool is detected, prompt for a one-line rationale (or read from
# $COVERAGE_RATIONALE env) and log to docs/.refactor-precondition.md so that
# /refactor can fold it into docs/refactor-report.md.
#
# Exit codes:
#   0 — pass (real check passed OR rationale fallback recorded)
#   1 — block (real check failed: tool reported below threshold,
#       OR empty rationale on rationale-prompt fallback)
#   2 — invalid configuration (bad threshold, internal error)
#
# Env / args:
#   $1                    target file or glob (passed to the tool when supported)
#   COVERAGE_THRESHOLD    integer 0..100 (default 80)
#   COVERAGE_RATIONALE    one-line rationale for non-interactive bypass
#   COVERAGE_FRAGMENT_OUT output fragment path
#                         (default: docs/.refactor-precondition.md)

set -uo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-80}"
TARGET="${1:-}"
FRAGMENT="${COVERAGE_FRAGMENT_OUT:-docs/.refactor-precondition.md}"

# --- Boundary: parse threshold ---
case "$THRESHOLD" in
  ''|*[!0-9]*)
    echo "coverage-precondition: BLOCKED: invalid COVERAGE_THRESHOLD='$THRESHOLD' (must be integer 0..100)" >&2
    exit 2
    ;;
esac
if [ "$THRESHOLD" -lt 0 ] || [ "$THRESHOLD" -gt 100 ]; then
  echo "coverage-precondition: BLOCKED: COVERAGE_THRESHOLD=$THRESHOLD out of range (0..100)" >&2
  exit 2
fi

mkdir -p "$(dirname "$FRAGMENT")" 2>/dev/null || true

# --- Shell: append a fragment to docs/.refactor-precondition.md ---
log_fragment() {
  local tool="$1" decision="$2" detail="${3:-}"
  {
    printf '\n## Coverage Precondition\n\n'
    printf -- '- detected_tool: %s\n' "$tool"
    printf -- '- threshold: %s%%\n' "$THRESHOLD"
    printf -- '- decision: %s\n' "$decision"
    if [ -n "$detail" ]; then
      printf -- '- detail: %s\n' "$detail"
    fi
  } >> "$FRAGMENT"
}

# --- Shell: read a rationale (env or stdin) and log it; fail closed on empty ---
prompt_rationale_and_log() {
  local reason="${1:-no coverage tool detected}"
  local rationale="${COVERAGE_RATIONALE:-}"
  if [ -z "$rationale" ]; then
    if [ -t 0 ]; then
      printf '▶ coverage precondition: %s — rationale required: ' "$reason" >&2
      IFS= read -r rationale || rationale=""
    else
      # non-interactive, read one line if available
      IFS= read -r rationale || rationale=""
    fi
  fi
  rationale="$(printf '%s' "$rationale" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$rationale" ]; then
    echo "coverage-precondition: BLOCKED: $reason and no rationale provided" >&2
    return 1
  fi
  {
    printf '\n## Coverage Precondition\n\n'
    printf -- '- detected_tool: none\n'
    printf -- '- threshold: %s%%\n' "$THRESHOLD"
    printf -- '- decision: bypass (rationale-fallback)\n'
    printf -- '- reason: %s\n' "$reason"
    printf -- '- rationale: %s\n' "$rationale"
  } >> "$FRAGMENT"
  echo "coverage-precondition: PASS via rationale-fallback (logged to $FRAGMENT)"
  return 0
}

# --- Tool runners ---
# Each runner returns: 0=pass, 1=block, 2=tool not applicable.
# Runners are dispatched indirectly via the RUNNERS array below, so static
# analysis cannot see the call sites.
# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table

run_pytest() {
  command -v pytest >/dev/null 2>&1 || return 2
  { [ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f pytest.ini ]; } || return 2
  local args=(--cov-fail-under="$THRESHOLD" --cov-report= -q)
  if [ -n "$TARGET" ]; then
    args+=(--cov="$TARGET")
  else
    args+=(--cov)
  fi
  if pytest "${args[@]}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_gotest() {
  command -v go >/dev/null 2>&1 || return 2
  [ -f go.mod ] || return 2
  local pkg="./..."
  if [ -n "$TARGET" ]; then
    # Allow either a directory or a Go package path
    pkg="./${TARGET%/}/..."
  fi
  local out
  out="$(go test -cover "$pkg" 2>&1)" || return 1
  # Extract `coverage: XX.X%` lines and take the minimum (or the only) value.
  local pct
  pct="$(printf '%s\n' "$out" | grep -oE 'coverage: [0-9.]+%' | awk '{print $2}' | tr -d '%' | sort -n | head -1)"
  if [ -z "$pct" ]; then
    return 2
  fi
  # Compare pct >= threshold using awk (float-aware).
  if awk -v p="$pct" -v t="$THRESHOLD" 'BEGIN { exit !(p+0 >= t+0) }'; then
    GO_LAST_PCT="$pct"
    return 0
  fi
  GO_LAST_PCT="$pct"
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_cargo_llvm_cov() {
  command -v cargo-llvm-cov >/dev/null 2>&1 || cargo --list 2>/dev/null | grep -q '^\s*llvm-cov' || return 2
  [ -f Cargo.toml ] || return 2
  if cargo llvm-cov --fail-under-lines "$THRESHOLD" --workspace >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_cargo_tarpaulin() {
  command -v cargo-tarpaulin >/dev/null 2>&1 || return 2
  [ -f Cargo.toml ] || return 2
  if cargo tarpaulin --fail-under "$THRESHOLD" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_vitest() {
  [ -f package.json ] || return 2
  grep -q '"vitest"' package.json 2>/dev/null || return 2
  command -v npx >/dev/null 2>&1 || return 2
  local args=(vitest run --coverage --coverage.thresholds.lines="$THRESHOLD")
  if [ -n "$TARGET" ]; then args+=("$TARGET"); fi
  if npx "${args[@]}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_jest() {
  [ -f package.json ] || return 2
  grep -q '"jest"' package.json 2>/dev/null || return 2
  command -v npx >/dev/null 2>&1 || return 2
  local threshold_json
  threshold_json="{\"global\":{\"lines\":${THRESHOLD}}}"
  local args=(jest --coverage --coverageThreshold="$threshold_json")
  if [ -n "$TARGET" ]; then args+=("$TARGET"); fi
  if npx "${args[@]}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329 # invoked indirectly via RUNNERS dispatch table
run_c8() {
  [ -f package.json ] || return 2
  grep -q '"c8"' package.json 2>/dev/null || return 2
  command -v npx >/dev/null 2>&1 || return 2
  if npx c8 --check-coverage --lines="$THRESHOLD" --reporter=text >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Detection order: first runner that returns 0 or 1 wins (i.e. tool was
# applicable). 2 means "skip — try next."
declare -a RUNNERS=(
  "pytest:run_pytest"
  "gotest:run_gotest"
  "cargo-llvm-cov:run_cargo_llvm_cov"
  "cargo-tarpaulin:run_cargo_tarpaulin"
  "vitest:run_vitest"
  "jest:run_jest"
  "c8:run_c8"
)

main() {
  GO_LAST_PCT=""
  for entry in "${RUNNERS[@]}"; do
    local name="${entry%%:*}"
    local fn="${entry##*:}"
    "$fn"
    local rc=$?
    case "$rc" in
      0)
        local detail=""
        [ "$name" = "gotest" ] && [ -n "$GO_LAST_PCT" ] && detail="coverage=${GO_LAST_PCT}%"
        log_fragment "$name" "pass" "$detail"
        echo "coverage-precondition: PASS via $name"
        exit 0
        ;;
      1)
        local detail="below threshold ${THRESHOLD}%"
        [ "$name" = "gotest" ] && [ -n "$GO_LAST_PCT" ] && detail="coverage=${GO_LAST_PCT}% (< ${THRESHOLD}%)"
        log_fragment "$name" "block" "$detail"
        echo "coverage-precondition: BLOCKED via $name (below ${THRESHOLD}%)" >&2
        exit 1
        ;;
      2) continue ;;
    esac
  done

  # No tool was applicable.
  prompt_rationale_and_log "no coverage tool detected" || exit 1
  exit 0
}

main "$@"
