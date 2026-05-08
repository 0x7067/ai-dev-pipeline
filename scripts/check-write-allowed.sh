#!/usr/bin/env bash
# check-write-allowed.sh — validate `write-allowed:` lines in agent / skill
# / command markdown front-matter.
#
# Layer: SHELL (file-system scan + lint). The "is this line acceptable"
# decision is a deterministic predicate, encoded inline.
#
# Accept rules:
#   - Path may start with a relative segment (no leading '/').
#   - Path may include the literal placeholders `${RUN_DIR}` or `${RUN_ID}`.
#   - Path may not contain `..` segments.
#   - Path may not be an absolute filesystem path.
#   - Empty / whitespace-only paths are rejected.
#   - The trailing `ONLY` marker / parenthetical comments are tolerated.
#
# Files scanned: any *.md under .claude/agents, .claude/skills, .claude/commands.
#
# Exit: 0 if all `write-allowed:` lines are clean; 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

errors=0

note() { echo "write-allowed: $*"; }
fail() { echo "write-allowed: ERROR: $*" >&2; errors=$((errors + 1)); }

# Strip placeholders before applying the absolute-path / traversal checks
# so they don't false-positive on legitimate `${RUN_DIR}` segments.
strip_placeholders() {
  # Single-quoted on purpose: we want the literal '${RUN_DIR}' text in
  # the sed pattern, not its expansion. SC2016 flags this as
  # potentially unintentional; suppress it.
  # shellcheck disable=SC2016
  printf '%s' "$1" | sed -e 's|\${RUN_DIR}||g' -e 's|\${RUN_ID}||g'
}

check_value() {
  local file="$1" line_no="$2" value="$3"
  # Trim surrounding whitespace and a trailing "ONLY" suffix or
  # parenthetical comment that some agents include for readability.
  local trimmed
  trimmed=$(printf '%s' "$value" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [ -z "$trimmed" ]; then
    fail "$file:$line_no: empty write-allowed value"
    return
  fi

  # The first token (up to whitespace) is the path; everything after is
  # commentary like "ONLY" or "(via Bash redirect `>`)" — we lint the path.
  local path
  path=$(printf '%s' "$trimmed" | awk '{print $1}')

  # Absolute-path check: only flag when the ORIGINAL path begins with
  # '/' (a real absolute path). Paths that start with `${RUN_DIR}/...`
  # are not absolute — `${RUN_DIR}` resolves to a relative dir at run
  # time. Traversal check uses the placeholder-stripped form so
  # `${RUN_DIR}` segments do not false-positive on `..`.
  case "$path" in
    /*) fail "$file:$line_no: absolute path not allowed: $path" ;;
  esac
  local stripped
  stripped=$(strip_placeholders "$path")
  case "$stripped" in
    *..*) fail "$file:$line_no: '..' segment not allowed: $path" ;;
  esac
}

scan_file() {
  local file="$1"
  # Only the front-matter region (between the first pair of '---' markers)
  # carries write-allowed declarations on agents. For skills/commands we
  # accept it anywhere in the body — they document the contract inline.
  local n=0
  # SC2094 false-positive here: check_value only writes to stderr,
  # not to "$file"; the read+write-same-file warning does not apply.
  # shellcheck disable=SC2094
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      write-allowed:*|*write-allowed:*)
        # Tolerate either `write-allowed: <value>` at line start or
        # within a code-block / inline reference.
        local value
        value=$(printf '%s' "$line" | sed -e 's/^.*write-allowed:[[:space:]]*//')
        check_value "$file" "$n" "$value"
        ;;
    esac
  done < "$file"
}

shopt -s nullglob 2>/dev/null || true

found=0
for dir in .claude/agents .claude/skills .claude/commands; do
  [ -d "$dir" ] || continue
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    found=$((found + 1))
    scan_file "$f"
  done < <(find "$dir" -type f -name '*.md' 2>/dev/null)
done

if [ "$found" -eq 0 ]; then
  note "no markdown files scanned (no .claude/{agents,skills,commands} dirs)"
fi

if [ "$errors" -gt 0 ]; then
  echo "write-allowed: FAILED with $errors issue(s)" >&2
  exit 1
fi

echo "write-allowed: OK ($found file(s) scanned)"
exit 0
