#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"

# Zero-setup support: if invoked from a consuming repo that has not vendored
# the gate runner (i.e. the script lives under ${CLAUDE_PLUGIN_ROOT}/scripts),
# stay in the consuming repo's CWD instead of cd'ing to the plugin install.
# Vendored installs (script lives in the repo) keep the original behavior.
verify_gates_repo_root="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"
if [ -f "${PWD}/scripts/run-verification-gates.sh" ] || [ "${PWD}" = "${verify_gates_repo_root}" ]; then
  harness_cd_repo_root
fi
unset verify_gates_repo_root

# ------------------------------------------------------------------------------
# Streaming output: each gate prints a ▶/✓/✗ line as it runs, so subagents and
# humans see progress in real time instead of waiting for the whole sequence
# to finish. Bash's echo/printf is line-buffered on newline; we additionally
# flush after every marker so output streams through pipes promptly.
# ------------------------------------------------------------------------------

emit() {
  printf '%s\n' "$*"
  # Best-effort flush; harmless if /dev/stdout is not a regular fd.
  { command sync || true; } >/dev/null 2>&1
}

run() {
  echo "verify-gates: $*"
  # If a gate-scoped resolved-command file is requested, record the
  # canonical argv so failure-path output can echo it back to the user.
  # Best-effort: missing file or write failure must not disrupt the gate.
  if [ -n "${GATE_RESOLVED_CMD_FILE:-}" ]; then
    printf '%s\n' "$*" > "$GATE_RESOLVED_CMD_FILE" 2>/dev/null || true
  fi
  "$@"
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

has_file_pattern() {
  local pattern="$1"
  local file="$2"

  if has_rg; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

has_package_script() {
  local script_name="$1"

  if [ ! -f package.json ]; then
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -e --arg script_name "$script_name" '.scripts[$script_name] != null' package.json >/dev/null 2>&1
    return $?
  fi

  has_file_pattern "\"${script_name}\"[[:space:]]*:" package.json
}

run_package_script() {
  local script_name="$1"
  local rc=0

  echo "verify-gates: package script: ${script_name}"
  harness_run_package_script "$script_name" || rc=$?
  if [ "$rc" -ne 127 ]; then
    return "$rc"
  fi

  echo "verify-gates: ERROR: package.json has ${script_name} script but no supported package manager found"
  return 1
}

# is_override_set: returns 0 iff the named env var is non-empty.
# Used to distinguish "user configured an explicit command" from "no override,
# fall back to default detection".
is_override_set() {
  local cmd_var="$1"
  [ -n "${!cmd_var:-}" ]
}

# run_override: runs the command stored in the named env var.
# Caller must have already verified the var is set via is_override_set.
# Returns the command's exit code; an override that fails is authoritative —
# callers MUST NOT fall back to default detection on failure, otherwise an
# explicit user override gets silently shadowed by the default hook.
run_override() {
  local label="$1"
  local cmd_var="$2"
  echo "==> ${label}"
  if [ -n "${GATE_RESOLVED_CMD_FILE:-}" ]; then
    printf '%s\n' "${!cmd_var}" > "$GATE_RESOLVED_CMD_FILE" 2>/dev/null || true
  fi
  run bash -c "${!cmd_var}"
}

run_typecheck() {
  if is_override_set "VERIFY_TYPECHECK_CMD"; then
    run_override "Type/compile" "VERIFY_TYPECHECK_CMD"
    return $?
  fi
  run bash .claude/hooks/type-check.sh
}

run_lint() {
  if is_override_set "VERIFY_LINT_CMD"; then
    run_override "Lint" "VERIFY_LINT_CMD"
    return $?
  fi
  run bash .claude/hooks/lint-on-edit.sh
}

run_security() {
  if is_override_set "VERIFY_SECURITY_CMD"; then
    run_override "Security" "VERIFY_SECURITY_CMD"
    return $?
  fi
  run bash scripts/security-scan.sh
}

run_property() {
  if is_override_set "VERIFY_PROPERTY_CMD"; then
    run_override "Property tests" "VERIFY_PROPERTY_CMD"
    return $?
  fi

  if has_package_script "test:property"; then
    run_package_script "test:property"
    return $?
  fi
  if has_package_script "property:test"; then
    run_package_script "property:test"
    return $?
  fi
  if has_package_script "property-tests"; then
    run_package_script "property-tests"
    return $?
  fi
  if has_package_script "property"; then
    run_package_script "property"
    return $?
  fi

  if [ "${VERIFY_REQUIRE_PROPERTY:-0}" = "1" ]; then
    echo "verify-gates: ERROR: VERIFY_REQUIRE_PROPERTY=1 but no property test command was found"
    return 1
  fi

  echo "verify-gates: Property tests skipped (no configured command)"
  return 0
}

run_contract() {
  if is_override_set "VERIFY_CONTRACT_CMD"; then
    run_override "Contract tests" "VERIFY_CONTRACT_CMD"
    return $?
  fi

  if has_package_script "test:contract"; then
    run_package_script "test:contract"
    return $?
  fi
  if has_package_script "contract:test"; then
    run_package_script "contract:test"
    return $?
  fi
  if has_package_script "contract-tests"; then
    run_package_script "contract-tests"
    return $?
  fi
  if has_package_script "contract"; then
    run_package_script "contract"
    return $?
  fi

  if [ "${VERIFY_REQUIRE_CONTRACT:-0}" = "1" ]; then
    echo "verify-gates: ERROR: VERIFY_REQUIRE_CONTRACT=1 but no contract test command was found"
    return 1
  fi

  echo "verify-gates: Contract tests skipped (no configured command)"
  return 0
}

run_full_suite() {
  if is_override_set "VERIFY_FULL_CMD"; then
    run_override "Full suite" "VERIFY_FULL_CMD"
    return $?
  fi

  if has_package_script "test"; then
    run_package_script "test"
    return $?
  fi

  if [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
    run cargo test
    return 0
  fi

  if [ -f go.mod ] && command -v go >/dev/null 2>&1; then
    run go test ./...
    return 0
  fi

  if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
    if command -v pytest >/dev/null 2>&1; then
      run pytest
      return 0
    fi
    if [ -d tests ] || [ -d test ]; then
      if command -v python3 >/dev/null 2>&1; then
        run python3 -m unittest discover
        return 0
      fi
      if command -v python >/dev/null 2>&1; then
        run python -m unittest discover
        return 0
      fi
    fi
  fi

  if [ "${VERIFY_REQUIRE_FULL_SUITE:-0}" = "1" ]; then
    echo "verify-gates: ERROR: VERIFY_REQUIRE_FULL_SUITE=1 but no full-suite test runner was found"
    return 1
  fi

  echo "verify-gates: Full suite skipped (no configured test runner)"
  return 0
}

export HOOKS_FAST="${HOOKS_FAST:-0}"

MAX_VERIFY_RETRIES="${MAX_VERIFY_RETRIES:-0}"
# Per-run hint file: when an active run is in flight (RUN_DIR set, or
# resolvable via docs/latest), the hint file lives under that run's dir
# so concurrent /ship sessions don't stomp each other. Falls back to
# the historical docs/.verify-retry.json default for repos that haven't
# minted a run yet.
if [ -z "${VERIFY_RETRY_HINT_FILE:-}" ]; then
  if [ -n "${RUN_DIR:-}" ]; then
    VERIFY_RETRY_HINT_FILE="${RUN_DIR}/.verify-retry.json"
  elif [ -n "${RUN_ID:-}" ]; then
    VERIFY_RETRY_HINT_FILE="docs/runs/${RUN_ID}/.verify-retry.json"
  else
    VERIFY_RETRY_HINT_FILE="docs/.verify-retry.json"
  fi
fi
VERIFY_REQUIRE_FULL_SUITE="${VERIFY_REQUIRE_FULL_SUITE:-0}"
VERIFY_REQUIRE_PROPERTY="${VERIFY_REQUIRE_PROPERTY:-0}"
VERIFY_REQUIRE_CONTRACT="${VERIFY_REQUIRE_CONTRACT:-0}"

if ! harness_is_non_negative_int "$MAX_VERIFY_RETRIES"; then
  echo "verify-gates: ERROR: MAX_VERIFY_RETRIES must be a non-negative integer"
  exit 1
fi

write_retry_hint() {
  local gate="$1"
  local exit_code="$2"
  local attempt="$3"
  mkdir -p "$(dirname "$VERIFY_RETRY_HINT_FILE")" 2>/dev/null || true
  # Atomic swap (write-tmp + rename) instead of in-place truncate:
  # parallel read-only gates can call this concurrently on the same
  # hint path; O_TRUNC + write is not atomic on regular files, so two
  # racing failures could briefly interleave bytes. The rename is
  # POSIX-atomic, so a reader always observes one complete JSON object
  # (last writer wins). Per-process tmp suffix prevents two writers
  # from racing on the tmp path itself.
  local tmp="${VERIFY_RETRY_HINT_FILE}.tmp.$$.${RANDOM:-0}"
  printf '{"gate":"%s","exit_code":%s,"attempt":%s}\n' "$gate" "$exit_code" "$attempt" > "$tmp"
  mv "$tmp" "$VERIFY_RETRY_HINT_FILE"
}

# Resolve a per-run scratch dir for the gate logs. Prefer ${RUN_DIR},
# fall back to a mktemp dir so the runner stays usable when invoked
# without an active run (smoke tests, CI bootstrap, etc.).
GATE_LOG_DIR=""
GATE_LOG_DIR_IS_TEMP=0
if [ -n "${RUN_DIR:-}" ]; then
  GATE_LOG_DIR="${RUN_DIR}"
  mkdir -p "$GATE_LOG_DIR" 2>/dev/null || true
elif [ -n "${RUN_ID:-}" ]; then
  GATE_LOG_DIR="docs/runs/${RUN_ID}"
  mkdir -p "$GATE_LOG_DIR" 2>/dev/null || true
else
  GATE_LOG_DIR="$(mktemp -d -t verify-gates.XXXXXX)"
  GATE_LOG_DIR_IS_TEMP=1
fi

cleanup_gate_log_dir() {
  if [ "$GATE_LOG_DIR_IS_TEMP" = "1" ] && [ -n "$GATE_LOG_DIR" ] && [ -d "$GATE_LOG_DIR" ]; then
    rm -rf "$GATE_LOG_DIR"
  fi
}
trap cleanup_gate_log_dir EXIT

# emit_failure_diagnostics <label>
#   On gate failure, surface the resolved command, the captured log path
#   (when available), and a one-line "rerun locally with: ..." hint so the
#   user can reproduce the failure without re-reading the runner internals.
#   Best-effort: missing files render as "(unknown)" rather than aborting.
emit_failure_diagnostics() {
  local label="$1"
  local cmd_file="${GATE_LOG_DIR}/.gate-${label}.cmd"
  local log_file="${GATE_LOG_DIR}/.gate-${label}.log"
  local resolved="(unknown — gate did not register a command)"
  if [ -s "$cmd_file" ]; then
    resolved="$(head -n1 "$cmd_file" 2>/dev/null)"
  fi
  emit "  resolved command: ${resolved}"
  if [ -f "$log_file" ]; then
    emit "  captured log:     ${log_file}"
  else
    emit "  captured log:     (none — sequential gate streamed to stdout above)"
  fi
  emit "  rerun locally with: ${resolved}"
}

# Bash's $SECONDS builtin gives us 1-second granularity portably (macOS + Linux).
# That's good enough for gate-level timing — gates take seconds to minutes.
run_gate() {
  local label="$1"
  local fn="$2"
  local attempt=0
  local rc=0
  local start_s
  local elapsed_s
  local cmd_file="${GATE_LOG_DIR}/.gate-${label}.cmd"
  : > "$cmd_file" 2>/dev/null || true
  while :; do
    start_s=$SECONDS
    if [ "$attempt" -eq 0 ]; then
      emit "▶ ${label} starting"
    else
      emit "↻ ${label} retry ${attempt}/${MAX_VERIFY_RETRIES}"
    fi
    rc=0
    GATE_RESOLVED_CMD_FILE="$cmd_file" "$fn" || rc=$?
    elapsed_s=$((SECONDS - start_s))
    if [ "$rc" -eq 0 ]; then
      emit "✓ ${label} ok (${elapsed_s}s)"
      return 0
    fi
    emit "✗ ${label} failed rc=${rc} (${elapsed_s}s)"
    emit_failure_diagnostics "$label"
    write_retry_hint "$label" "$rc" "$attempt"
    if [ "$attempt" -ge "$MAX_VERIFY_RETRIES" ]; then
      return "$rc"
    fi
    attempt=$((attempt + 1))
  done
}

# Reset hint file on each run.
mkdir -p "$(dirname "$VERIFY_RETRY_HINT_FILE")" 2>/dev/null || true
: > "$VERIFY_RETRY_HINT_FILE" 2>/dev/null || true

# ------------------------------------------------------------------------------
# Parallel read-only gate fan-out
# ------------------------------------------------------------------------------
# typecheck / lint / security are CPU-bound and read-only: they don't
# mutate workspace state and their results don't depend on each other.
# We fan them out as background jobs writing to per-gate log files and
# then replay the logs in fixed order (typecheck → lint → security)
# after the join. Determinism > marginal latency: if any gate fails we
# still wait for the siblings rather than early-killing them, so log
# diffs across CI runs stay stable.
#
# Test gates (property / contract / full_suite) remain sequential —
# they often share file-system state (caches, build artifacts) and
# parallelizing them is out of scope for this change.
# ------------------------------------------------------------------------------

# run_gate_to_log <label> <fn>
#   Same retry / timing semantics as run_gate, but every byte of gate
#   output is funneled into ${GATE_LOG_DIR}/.gate-<label>.log and the
#   final exit code is written to .gate-<label>.rc. The function itself
#   prints nothing on stdout/stderr — replay_gate_log prints it later.
run_gate_to_log() {
  local label="$1"
  local fn="$2"
  local log="${GATE_LOG_DIR}/.gate-${label}.log"
  local rc_file="${GATE_LOG_DIR}/.gate-${label}.rc"
  local cmd_file="${GATE_LOG_DIR}/.gate-${label}.cmd"
  local attempt=0
  local rc=0
  local start_s
  local elapsed_s
  : > "$log"
  : > "$rc_file"
  : > "$cmd_file"
  while :; do
    start_s=$SECONDS
    if [ "$attempt" -eq 0 ]; then
      printf '▶ %s starting\n' "$label" >> "$log"
    else
      printf '↻ %s retry %s/%s\n' "$label" "$attempt" "$MAX_VERIFY_RETRIES" >> "$log"
    fi
    rc=0
    GATE_RESOLVED_CMD_FILE="$cmd_file" "$fn" >> "$log" 2>&1 || rc=$?
    elapsed_s=$((SECONDS - start_s))
    if [ "$rc" -eq 0 ]; then
      printf '✓ %s ok (%ss)\n' "$label" "$elapsed_s" >> "$log"
      printf '0\n' > "$rc_file"
      return 0
    fi
    printf '✗ %s failed rc=%s (%ss)\n' "$label" "$rc" "$elapsed_s" >> "$log"
    write_retry_hint "$label" "$rc" "$attempt"
    if [ "$attempt" -ge "$MAX_VERIFY_RETRIES" ]; then
      printf '%s\n' "$rc" > "$rc_file"
      return "$rc"
    fi
    attempt=$((attempt + 1))
  done
}

replay_gate_log() {
  local label="$1"
  local log="${GATE_LOG_DIR}/.gate-${label}.log"
  if [ -f "$log" ]; then
    cat "$log"
  else
    emit "✗ ${label} log missing"
  fi
}

read_gate_rc() {
  local label="$1"
  local rc_file="${GATE_LOG_DIR}/.gate-${label}.rc"
  if [ -f "$rc_file" ] && [ -s "$rc_file" ]; then
    cat "$rc_file"
  else
    # Missing rc file = the background job died before writing it.
    echo 1
  fi
}

OVERALL_START_S=$SECONDS
emit "▶ verification gates starting (6 gates: 3 parallel read-only + 3 sequential test)"

# --- parallel block: typecheck + lint + security ---
parallel_start_s=$SECONDS
emit "▶ read-only gates fan-out (typecheck, lint, security)"
run_gate_to_log typecheck run_typecheck &
pid_typecheck=$!
run_gate_to_log lint run_lint &
pid_lint=$!
run_gate_to_log security run_security &
pid_security=$!

# Wait on each sibling. We DO NOT propagate `wait` exit codes here — the
# authoritative rc lives in .gate-<label>.rc files written by run_gate_to_log.
wait "$pid_typecheck" 2>/dev/null || true
wait "$pid_lint"      2>/dev/null || true
wait "$pid_security"  2>/dev/null || true

parallel_elapsed_s=$((SECONDS - parallel_start_s))

# Replay in deterministic order: typecheck → lint → security.
replay_gate_log typecheck
replay_gate_log lint
replay_gate_log security

rc_typecheck=$(read_gate_rc typecheck)
rc_lint=$(read_gate_rc lint)
rc_security=$(read_gate_rc security)

emit "↦ read-only gates joined (${parallel_elapsed_s}s wall; rc typecheck=${rc_typecheck} lint=${rc_lint} security=${rc_security})"

# Aggregate. First non-zero rc, in fixed order, is what we exit with.
# This preserves "any read-only gate failure stops the test gates"
# semantics from the sequential form.
for pair in "typecheck:$rc_typecheck" "lint:$rc_lint" "security:$rc_security"; do
  _label="${pair%%:*}"; _rc="${pair#*:}"
  if [ "$_rc" != "0" ]; then
    emit_failure_diagnostics "$_label"
    emit "✗ verification gates failed in read-only block"
    exit "$_rc"
  fi
done
unset _label _rc

# --- sequential block: property → contract → full_suite ---
run_gate property run_property
run_gate contract run_contract
run_gate full_suite run_full_suite

OVERALL_ELAPSED_S=$((SECONDS - OVERALL_START_S))
emit "✓ all verification gates passed (${OVERALL_ELAPSED_S}s)"
