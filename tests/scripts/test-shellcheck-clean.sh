#!/usr/bin/env bash
# Guard test: shellcheck must report zero findings across all maintained
# shell scripts. CI environments without shellcheck installed skip cleanly
# (exit 0) so this gate doesn't block contributors who can't install it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not installed; skipping (exit 0)"
  exit 0
fi

cd "$REPO_ROOT" || exit 1

# Build the list of files we care about. Use globs that may not match (e.g.
# scripts/lib/ is currently absent) and filter to existing files only.
files=()
for pat in scripts/*.sh scripts/lib/*.sh tests/scripts/*.sh; do
  for f in $pat; do
    [ -f "$f" ] && files+=("$f")
  done
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "no shell scripts found; nothing to check"
  exit 0
fi

out="$(shellcheck "${files[@]}" 2>&1)"
rc=$?

if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  printf 'shellcheck-clean: ok (%d files)\n' "${#files[@]}"
  exit 0
fi

printf 'shellcheck-clean: FAIL — findings:\n' >&2
# Print the first 20 finding-block lines (each finding spans ~4 lines, so
# this is roughly the first 5 findings).
printf '%s\n' "$out" | head -80 >&2
exit 1
