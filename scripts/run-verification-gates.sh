#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

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
VERIFY_RETRY_HINT_FILE="${VERIFY_RETRY_HINT_FILE:-docs/.verify-retry.json}"
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
  printf '{"gate":"%s","exit_code":%s,"attempt":%s}\n' "$gate" "$exit_code" "$attempt" >> "$VERIFY_RETRY_HINT_FILE"
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
  while :; do
    start_s=$SECONDS
    if [ "$attempt" -eq 0 ]; then
      emit "▶ ${label} starting"
    else
      emit "↻ ${label} retry ${attempt}/${MAX_VERIFY_RETRIES}"
    fi
    rc=0
    "$fn" || rc=$?
    elapsed_s=$((SECONDS - start_s))
    if [ "$rc" -eq 0 ]; then
      emit "✓ ${label} ok (${elapsed_s}s)"
      return 0
    fi
    emit "✗ ${label} failed rc=${rc} (${elapsed_s}s)"
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

OVERALL_START_S=$SECONDS
emit "▶ verification gates starting (6 gates)"

# Run sequentially. set -e propagates the first non-zero rc to the caller.
run_gate typecheck run_typecheck
run_gate lint run_lint
run_gate security run_security
run_gate property run_property
run_gate contract run_contract
run_gate full_suite run_full_suite

OVERALL_ELAPSED_S=$((SECONDS - OVERALL_START_S))
emit "✓ all verification gates passed (${OVERALL_ELAPSED_S}s)"
