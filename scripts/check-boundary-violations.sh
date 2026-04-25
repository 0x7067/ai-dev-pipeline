#!/usr/bin/env bash
set -euo pipefail

# Heuristic guardrail for early detection. Real enforcement should be backed by tests and linters.
#
# LANGUAGE COVERAGE: The default BOUNDARY_INGRESS_REGEX covers JavaScript/TypeScript only
# (process.env, JSON.parse, req.body, localStorage.getItem). For other languages, override
# BOUNDARY_INGRESS_REGEX with appropriate patterns before running:
#   Python:  BOUNDARY_INGRESS_REGEX='os\.environ|json\.load\(|request\.(json|form|args)'
#   Go:      BOUNDARY_INGRESS_REGEX='os\.Getenv|json\.Unmarshal|r\.FormValue'
#   Rust:    BOUNDARY_INGRESS_REGEX='std::env::var|serde_json::from_str'

tmp_file="$(mktemp "${TMPDIR:-/tmp}/boundary_hits.XXXXXX")"
cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

detect_language_regex() {
  if [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ]; then
    echo 'os\.environ|json\.load\(|request\.(json|form|args)'
  elif [ -f go.mod ]; then
    echo 'os\.Getenv|json\.Unmarshal|r\.FormValue'
  elif [ -f Cargo.toml ]; then
    echo 'std::env::var|serde_json::from_str'
  elif [ -f package.json ] || [ -f tsconfig.json ]; then
    echo 'process\.env|JSON\.parse\(|req\.body|localStorage\.getItem\('
  else
    echo 'process\.env|JSON\.parse\(|req\.body|localStorage\.getItem\('
  fi
}

strict_mode="${BOUNDARY_CHECK_STRICT:-0}"
src_dirs_raw="${BOUNDARY_SRC_DIRS:-src}"
ingress_regex="${BOUNDARY_INGRESS_REGEX:-$(detect_language_regex)}"
core_glob="${BOUNDARY_CORE_GLOB:-**/core/**}"
domain_glob="${BOUNDARY_DOMAIN_GLOB:-**/domain/**}"

has_rg() {
  command -v rg >/dev/null 2>&1
}

glob_to_ere() {
  local glob="$1"

  # Escape regex metacharacters except glob markers.
  glob="$(printf '%s' "$glob" | sed 's/[].[^$+(){}|\\]/\\&/g')"
  glob="${glob//\*\*/__DOUBLE_STAR__}"
  glob="${glob//\*/[^/]*}"
  glob="${glob//\?/[^/]}"
  glob="${glob//__DOUBLE_STAR__/.*}"

  printf '%s' "^${glob}$"
}

search_with_glob() {
  local dir="$1"
  local path_glob="$2"
  local pattern="$3"
  local out_file="$4"

  if has_rg; then
    rg -n --glob "$path_glob" "$pattern" "$dir" >"$out_file" 2>/dev/null
    return $?
  fi

  local path_regex
  path_regex="$(glob_to_ere "$path_glob")"

  grep -R -n -E -- "$pattern" "$dir" 2>/dev/null |
    awk -F: -v path_re="$path_regex" '$1 ~ path_re { print }' >"$out_file"

  [ -s "$out_file" ]
}

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

  if search_with_glob "$dir" "$path_glob" "$pattern" "$tmp_file"; then
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
