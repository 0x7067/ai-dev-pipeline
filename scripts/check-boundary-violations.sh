#!/usr/bin/env bash
set -euo pipefail

# Heuristic guardrail for early detection. Real enforcement should be backed by tests and linters.

tmp_file="$(mktemp "${TMPDIR:-/tmp}/boundary_hits.XXXXXX")"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

if [ ! -d src ]; then
  echo "boundary-check: skipped (no src directory)"
  exit 0
fi

errors=0

check_pattern() {
  local path_glob="$1"
  local pattern="$2"
  local label="$3"

  if rg -n --glob "$path_glob" "$pattern" src >"$tmp_file" 2>/dev/null; then
    echo "boundary-check: ERROR: found $label in files matching $path_glob"
    cat "$tmp_file"
    errors=$((errors + 1))
  fi
}

check_pattern '**/core/**' 'process\.env|JSON\.parse\(|req\.body|localStorage\.getItem\(' 'raw ingress usage in core'
check_pattern '**/domain/**' 'process\.env|JSON\.parse\(|req\.body|localStorage\.getItem\(' 'raw ingress usage in domain'

if [ "$errors" -gt 0 ]; then
  echo "boundary-check: FAILED with $errors violation group(s)"
  exit 1
fi

echo "boundary-check: OK"
