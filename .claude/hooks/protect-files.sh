#!/usr/bin/env bash
set -euo pipefail

PROTECTED_REGEX='(^|/)(\.env(\..+)?|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|bun\.lockb|Cargo\.lock|Pipfile\.lock|poetry\.lock|Gemfile\.lock|.*\.(pem|key|p12|jks|keystore))$'

payload="${1:-}"
if [ -z "$payload" ] && [ ! -t 0 ]; then
  payload="$(cat || true)"
fi

is_protected_path() {
  local path="$1"
  [[ "$path" =~ $PROTECTED_REGEX ]]
}

check_and_block() {
  local path="$1"
  if is_protected_path "$path"; then
    echo "protect-files: blocked edit/write on protected file: $path"
    exit 2
  fi
}

if [ -n "$payload" ]; then
  extracted_paths=()
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r extracted_path; do
      [ -n "$extracted_path" ] || continue
      extracted_paths+=("$extracted_path")
    done < <(printf '%s' "$payload" | jq -r '.. | objects | .file_path? // empty | strings' 2>/dev/null || true)
  fi

  if [ "${#extracted_paths[@]}" -gt 0 ]; then
    for path in "${extracted_paths[@]}"; do
      check_and_block "$path"
    done
  else
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      check_and_block "$path"
    done <<< "$payload"
  fi
fi

exit 0
