# project-root.sh — resolve the target project root for run artifacts.
# shellcheck shell=bash
#
# Boundary parser (per .claude/rules/boundary-parse-dont-validate.md):
# inputs are the untrusted env vars CLAUDE_PROJECT_DIR and the current
# working directory; output is a single absolute, canonicalized directory
# path or non-zero exit. Consumers must not re-read the raw env.
#
# FC/IS placement: BOUNDARY (this is the parse-at-ingress layer for the
# untrusted CLAUDE_PROJECT_DIR env var). The functions perform minimal
# filesystem reads (`cd … && pwd -P`) to canonicalize the input; they have
# no other side effects and read no ambient state besides the documented env
# vars. Core never calls these — shell callers (ship orchestrator,
# mint-run-id, prune-runs, resolve-run, plan-gate) consume the parsed values
# to anchor artifact paths.
#
# Why this exists: harness_cd_repo_root() in scripts/harness-lib.sh is
# deliberately anchored to the plugin checkout for plugin self-validation.
# Run artifacts must instead land inside the consumer project. This helper
# is the single, typed source of that anchor.
#
# Usage:
#   source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/project-root.sh"
#   AIDP_PROJECT_ROOT="$(aidp_resolve_project_root)" || exit 1

if [ -n "${_AIDP_PROJECT_ROOT_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
_AIDP_PROJECT_ROOT_LOADED=1

# Resolve project root.
#
# Precedence:
#   1. $CLAUDE_PROJECT_DIR (Claude Code-provided absolute path)
#   2. $(pwd) fallback
#
# Fails closed (non-zero exit, empty stdout) if the candidate is not a
# directory or cannot be canonicalized.
aidp_resolve_project_root() {
  local candidate="${CLAUDE_PROJECT_DIR:-}"
  if [ -z "$candidate" ]; then
    candidate="$(pwd)"
  fi
  if [ -z "$candidate" ] || [ ! -d "$candidate" ]; then
    return 1
  fi
  local resolved
  resolved="$(cd "$candidate" >/dev/null 2>&1 && pwd -P)" || return 1
  if [ -z "$resolved" ] || [ ! -d "$resolved" ]; then
    return 1
  fi
  printf '%s\n' "$resolved"
}

# Resolve the artifacts root (the directory that holds runs/, latest,
# latest.txt, latest-green.txt, and standalone reports) for a given
# project root.
#
# Policy: unconditionally returns `${root}/docs/aidp` for every caller —
# consumer projects and the plugin's own self-development checkout alike.
# This is a pure string operation: no filesystem reads after the initial
# canonicalization of the input path.
#
# Inputs: $1 (optional) = project root; defaults to $AIDP_PROJECT_ROOT.
# Output: absolute artifacts root path; non-zero exit on missing/invalid input.
aidp_resolve_artifacts_root() {
  local root="${1:-${AIDP_PROJECT_ROOT:-}}"
  if [ -z "$root" ] || [ ! -d "$root" ]; then
    return 1
  fi
  local resolved
  resolved="$(cd "$root" >/dev/null 2>&1 && pwd -P)" || return 1
  printf '%s/docs/aidp\n' "$resolved"
}
