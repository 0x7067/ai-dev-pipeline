#!/usr/bin/env bash
set -euo pipefail

# Heuristic guardrail for early detection. Real enforcement should be backed by tests and linters.

tmp_file="$(mktemp "${TMPDIR:-/tmp}/boundary_hits.XXXXXX")"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

strict_mode="${BOUNDARY_CHECK_STRICT:-0}"
src_dirs_raw="${BOUNDARY_SRC_DIRS:-src}"
ingress_regex="${BOUNDARY_INGRESS_REGEX:-process\.env|JSON\.parse\(|req\.body|localStorage\.getItem\(}"
core_glob="${BOUNDARY_CORE_GLOB:-**/core/**}"
domain_glob="${BOUNDARY_DOMAIN_GLOB:-**/domain/**}"

IFS=',' read -ra src_dirs <<< "$src_dirs_raw"
valid_dirs=()
for dir in "${src_dirs[@]}"; do
  dir="$(printf '%s' "$dir" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$dir" ] || continue
  if [ -d "$dir" ]; then
    valid_dirs+=("$dir")
  fi
done

if [ "${#valid_dirs[@]}" -eq 0 ]; then
  if [ "$strict_mode" = "1" ]; then
    echo "boundary-check: ERROR: no boundary source directories found (set BOUNDARY_SRC_DIRS)"
    exit 1
  fi
  echo "boundary-check: skipped (no boundary source directories found)"
  exit 0
fi

errors=0

check_pattern() {
  local path_glob="$1"
  local pattern="$2"
  local label="$3"

  if rg -n --glob "$path_glob" "$pattern" "$dir" >"$tmp_file" 2>/dev/null; then
    echo "boundary-check: ERROR: found $label in files matching $path_glob"
    cat "$tmp_file"
    errors=$((errors + 1))
  fi
}

for dir in "${valid_dirs[@]}"; do
  check_pattern "${dir}/${core_glob}" "$ingress_regex" "raw ingress usage in core"
  check_pattern "${dir}/${domain_glob}" "$ingress_regex" "raw ingress usage in domain"
done

if [ "$errors" -gt 0 ]; then
  echo "boundary-check: FAILED with $errors violation group(s)"
  exit 1
fi

echo "boundary-check: OK"
