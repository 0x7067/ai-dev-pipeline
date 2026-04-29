#!/usr/bin/env bash
set -euo pipefail

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

  if command -v bun >/dev/null 2>&1; then
    run bun run -s "$script_name"
    return $?
  fi

  if command -v npm >/dev/null 2>&1; then
    run npm run -s "$script_name"
    return $?
  fi

  if command -v pnpm >/dev/null 2>&1; then
    run pnpm -s "$script_name"
    return $?
  fi

  if command -v yarn >/dev/null 2>&1; then
    run yarn -s "$script_name"
    return $?
  fi

  echo "verify-gates: ERROR: package.json has ${script_name} script but no supported package manager found"
  return 1
}

run_if_set() {
  local label="$1"
  local cmd_var="$2"

  if [ -n "${!cmd_var:-}" ]; then
    echo "==> ${label}"
    run bash -c "${!cmd_var}"
    return $?
  fi

  return 1
}

run_typecheck() {
  if run_if_set "Type/compile" "VERIFY_TYPECHECK_CMD"; then return 0; fi
  run bash .claude/hooks/type-check.sh
}

run_lint() {
  if run_if_set "Lint" "VERIFY_LINT_CMD"; then return 0; fi
  run bash .claude/hooks/lint-on-edit.sh
}

run_security() {
  if run_if_set "Security" "VERIFY_SECURITY_CMD"; then return 0; fi
  run bash scripts/security-scan.sh
}

run_property() {
  if run_if_set "Property tests" "VERIFY_PROPERTY_CMD"; then return 0; fi

  if has_package_script "test:property"; then
    run_package_script "test:property"
    return 0
  fi
  if has_package_script "property:test"; then
    run_package_script "property:test"
    return 0
  fi
  if has_package_script "property-tests"; then
    run_package_script "property-tests"
    return 0
  fi
  if has_package_script "property"; then
    run_package_script "property"
    return 0
  fi

  echo "verify-gates: Property tests skipped (no configured command)"
  return 0
}

run_contract() {
  if run_if_set "Contract tests" "VERIFY_CONTRACT_CMD"; then return 0; fi

  if has_package_script "test:contract"; then
    run_package_script "test:contract"
    return 0
  fi
  if has_package_script "contract:test"; then
    run_package_script "contract:test"
    return 0
  fi
  if has_package_script "contract-tests"; then
    run_package_script "contract-tests"
    return 0
  fi
  if has_package_script "contract"; then
    run_package_script "contract"
    return 0
  fi

  echo "verify-gates: Contract tests skipped (no configured command)"
  return 0
}

run_full_suite() {
  if run_if_set "Full suite" "VERIFY_FULL_CMD"; then return 0; fi

  if has_package_script "test"; then
    run_package_script "test"
    return 0
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

  echo "verify-gates: Full suite skipped (no configured test runner)"
  return 0
}

export HOOKS_FAST="${HOOKS_FAST:-0}"

run_typecheck
run_lint
run_security
run_property
run_contract
run_full_suite
