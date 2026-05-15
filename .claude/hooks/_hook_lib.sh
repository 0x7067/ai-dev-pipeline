# shellcheck shell=bash
# Shared utilities for Claude Code PostToolUse hooks.
# Usage: set HOOK_NAME before sourcing this file.
#   HOOK_NAME="lint-on-edit"
#   source "$(dirname "$0")/_hook_lib.sh"

: "${HOOK_NAME:?HOOK_NAME must be set before sourcing _hook_lib.sh}"

# Early exit: skip files outside project directory.
# Skip the stdin read entirely when sourced for utility-only access
# (HOOK_LIB_NO_STDIN=1) — PreToolUse hooks consume their own stdin and
# cannot let this file race them for the payload.
if [ "${HOOK_LIB_NO_STDIN:-0}" != "1" ]; then
  _hook_payload="$(cat)"
  _edited_file=""
  if [ -n "$_hook_payload" ]; then
    if command -v jq >/dev/null 2>&1; then
      _edited_file="$(printf '%s' "$_hook_payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
    fi
  fi
  if [ -n "$_edited_file" ]; then
    case "$_edited_file" in
      "$PWD"/*) ;;
      *) echo "${HOOK_NAME}: skipped (file outside project)"; exit 0 ;;
    esac
  fi
fi

run() {
  echo "${HOOK_NAME}: $*"
  "$@"
}

# Compaction policy for advisory stderr injection. The harness re-injects
# stderr as a system-reminder; verbose lint/typecheck output (ESLint stylish,
# tsc, ruff, golangci) burns the agent's context budget on near-duplicate
# lines. Set HOOK_OUTPUT_COMPACT=0 to disable; HOOK_OUTPUT_MAX_LINES tunes
# the passthrough threshold.
HOOK_OUTPUT_COMPACT="${HOOK_OUTPUT_COMPACT:-1}"
HOOK_OUTPUT_MAX_LINES="${HOOK_OUTPUT_MAX_LINES:-30}"

# compact_tool_output: pure stream transform. Reads stdin, writes either the
# original text (when input is short or no recognised pattern matches) or a
# compacted summary grouping findings by (file, rule) → line list. Never
# fails; always exits 0.
#
# Recognised input formats:
#   - ESLint stylish: a bare path line, then "  L:C  level  msg  rule"
#   - tsc:            "path(L,C): error TSxxxx: msg"
#   - ruff/golangci:  "path:L:C: CODE msg"
#
# Awk dialect: portable (no gawk-only 3-arg match). SUBSEP is used to build
# composite keys; substr+sub do the field extraction. The function is
# FC-style: deterministic over its input, no side effects beyond stdout.
compact_tool_output() {
  if [ "${HOOK_OUTPUT_COMPACT}" = "0" ]; then
    cat
    return 0
  fi
  awk -v max_lines="${HOOK_OUTPUT_MAX_LINES}" '
    { all[NR] = $0 }
    NF == 1 && /^[^[:space:]]+\.[a-zA-Z]+$/ { current_file = $0; next }
    /^[[:space:]]+[0-9]+:[0-9]+[[:space:]]+(error|warning)[[:space:]]/ {
      s = $0; sub(/^[[:space:]]+/, "", s)
      ln = s; sub(/:.*/, "", ln)
      rule = $NF
      key = current_file SUBSEP rule
      counts[key]++
      linenums[key] = (linenums[key] == "" ? ln : linenums[key] "," ln)
      matched = 1
      next
    }
    match($0, /^.+\([0-9]+,[0-9]+\):[[:space:]]+error[[:space:]]+TS[0-9]+:/) {
      s = substr($0, RSTART, RLENGTH)
      f = s; sub(/\(.*/, "", f)
      ln = s; sub(/^[^(]+\(/, "", ln); sub(/,.*/, "", ln)
      rule = s; sub(/^.*error[[:space:]]+/, "", rule); sub(/:.*/, "", rule)
      key = f SUBSEP rule
      counts[key]++
      linenums[key] = (linenums[key] == "" ? ln : linenums[key] "," ln)
      matched = 1
      next
    }
    match($0, /^[^:[:space:]]+:[0-9]+:[0-9]+:[[:space:]]+[A-Z][A-Z0-9]+[[:space:]]/) {
      s = substr($0, RSTART, RLENGTH)
      n = split(s, parts, ":")
      f = parts[1]; ln = parts[2]
      rest = parts[4]; sub(/^[[:space:]]+/, "", rest)
      rule = rest; sub(/[[:space:]].*/, "", rule)
      key = f SUBSEP rule
      counts[key]++
      linenums[key] = (linenums[key] == "" ? ln : linenums[key] "," ln)
      matched = 1
      next
    }
    { context[++ctx_n] = $0 }
    END {
      total_in = NR
      if (total_in <= max_lines || !matched) {
        for (i = 1; i <= total_in; i++) print all[i]
        exit 0
      }
      printf "compacted from %d output lines:\n", total_in
      grouped = 0
      for (k in counts) {
        split(k, parts, SUBSEP)
        f = (parts[1] != "" ? parts[1] : "<unknown file>")
        rule = parts[2]
        printf "  %s × %d: %s — lines %s\n", rule, counts[k], f, linenums[k]
        grouped += counts[k]
      }
      if (ctx_n > 0) {
        keep = (ctx_n < 8 ? ctx_n : 8)
        print "context:"
        for (i = 1; i <= keep; i++) print "  " context[i]
        if (ctx_n > keep) printf "  … +%d more context lines\n", ctx_n - keep
      }
      printf "(%d findings grouped; set HOOK_OUTPUT_COMPACT=0 to see full output)\n", grouped
    }
  '
}

# Run a tool advisorily: capture combined output; on failure pipe through
# compact_tool_output to stderr and exit 1 (non-blocking). Never exit 2
# (which Claude treats as blocking).
run_advisory() {
  echo "${HOOK_NAME}: $*"
  local _out _rc
  _out="$("$@" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -ne 0 ]; then
    printf '%s\n' "$_out" | compact_tool_output >&2
    echo "${HOOK_NAME}: command failed (exit $_rc) — reported as advisory" >&2
    exit 1
  fi
  exit 0
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

has_input_pattern() {
  local pattern="$1"

  if has_rg; then
    rg -q -- "$pattern"
  else
    grep -Eq -- "$pattern"
  fi
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

filter_changed_files() {
  local pattern="$1"

  if has_rg; then
    rg -- "$pattern"
  else
    grep -E -- "$pattern"
  fi
}

# Hooks run without a TTY and with no human at the prompt. Signal that
# to any child process via the conventions tooling commonly respects, so
# they pick stream output, skip prompts, and don't try to enter a TUI.
# Each var is only set if the caller hasn't already pinned a value.
#
# - CI=1            : near-universal "non-interactive" switch (turbo,
#                     pnpm, npm, jest, vitest, husky, lint-staged, …).
# - NO_COLOR=1      : project convention (.claude/rules/output-style.md);
#                     also prevents ANSI bleed into captured stderr.
# - NPM_CONFIG_*    : silences fund/audit chatter on `npm`/`pnpm` runs.
# - TURBO_UI=false  : belt-and-suspenders for turbo.json with a hard-
#                     coded `"ui": "tui"`, which has historically ignored
#                     CI detection and emitted only the banner before
#                     exiting non-zero — surfaced as a spurious
#                     "PostToolUse hook error" on every Edit.
export CI="${CI:-1}"
export NO_COLOR="${NO_COLOR:-1}"
export NPM_CONFIG_FUND="${NPM_CONFIG_FUND:-false}"
export NPM_CONFIG_AUDIT="${NPM_CONFIG_AUDIT:-false}"
export TURBO_UI="${TURBO_UI:-false}"

fast_mode="${HOOKS_FAST:-1}"
changed_files_list=""

if [ "$fast_mode" = "1" ] && command -v git >/dev/null 2>&1; then
  changed_files_list="$(
    {
      git diff --name-only --diff-filter=ACM 2>/dev/null || true
      git ls-files -m -o --exclude-standard 2>/dev/null || true
    } | sort -u
  )"
fi

has_changed_ext() {
  local ext_pattern="$1"
  [ -n "$changed_files_list" ] || return 1
  printf '%s\n' "$changed_files_list" | has_input_pattern "${ext_pattern}$"
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

detect_pkg_manager() {
  # Prefer lockfile — reflects what the project actually uses.
  # Only echo if the corresponding binary is available; otherwise fall through.
  if { [ -f bun.lockb ] || [ -f bun.lock ]; } && command -v bun  >/dev/null 2>&1; then echo bun; return; fi
  if [ -f pnpm-lock.yaml ]                    && command -v pnpm >/dev/null 2>&1; then echo pnpm; return; fi
  if [ -f yarn.lock ]                         && command -v yarn >/dev/null 2>&1; then echo yarn; return; fi
  if [ -f package-lock.json ]                 && command -v npm  >/dev/null 2>&1; then echo npm; return; fi
  # No matching lockfile+binary — fall back to first available binary.
  local _pm
  for _pm in bun pnpm yarn npm; do
    command -v "$_pm" >/dev/null 2>&1 && { echo "$_pm"; return; }
  done
}

# resolve_workflow_state_path: prints the path of the workflow-state JSON
# file the hooks should read/write. Resolution order, fail-soft:
#   1. $WORKFLOW_STATE_PATH if explicitly set (orchestrator override).
#   2. <project>/.claude/workflow-state/<active>.json when an active pointer
#      exists AND the active value parses through scripts/parse-run-id.sh.
#   3. <project>/.claude/workflow-state.json (legacy single-state default).
# Anchors to AIDP_PROJECT_ROOT (CLAUDE_PROJECT_DIR → $(pwd)). Never echoes
# an unparsed run-id; falls back to legacy on parse failure.
resolve_workflow_state_path() {
  if [ -n "${WORKFLOW_STATE_PATH:-}" ]; then
    printf '%s\n' "$WORKFLOW_STATE_PATH"
    return 0
  fi
  local _proj_raw="${AIDP_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  # Canonicalize to keep results stable across /tmp ↔ /private/tmp style
  # OS symlinks (matches aidp_resolve_project_root's pwd -P behavior).
  #
  # INTENTIONAL DIVERGENCE from scripts/lib/project-root.sh: this hook
  # helper fail-SOFTS on a non-existent project root (returns the raw
  # path), whereas aidp_resolve_project_root fail-CLOSES (non-zero exit).
  # Reason: PostToolUse hooks must NEVER block editing on a missing
  # working-tree directory — falling back to the raw path lets the
  # downstream consumer (resolve_workflow_state_path callers) emit a
  # path the user can inspect, instead of aborting the user's edit.
  local _proj
  _proj="$(cd "$_proj_raw" >/dev/null 2>&1 && pwd -P)" || _proj="$_proj_raw"
  local active_file="${_proj}/.claude/workflow-state/active"
  local parser
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/parse-run-id.sh" ]; then
    parser="${CLAUDE_PLUGIN_ROOT}/scripts/parse-run-id.sh"
  else
    parser="${_proj}/scripts/parse-run-id.sh"
  fi
  if [ -f "$active_file" ] && [ -f "$parser" ]; then
    local active
    active=$(head -n1 "$active_file" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$active" ] && bash "$parser" "$active" >/dev/null 2>&1; then
      printf '%s/.claude/workflow-state/%s.json\n' "$_proj" "$active"
      return 0
    fi
  fi
  printf '%s/.claude/workflow-state.json\n' "$_proj"
}

# Detect Python package manager (uv > poetry > pip).
# Lockfile presence + binary availability required; falls back to pip if any Python project marker exists.
detect_py_pkg_manager() {
  if [ -f uv.lock ]      && command -v uv     >/dev/null 2>&1; then echo uv; return; fi
  if [ -f poetry.lock ]  && command -v poetry >/dev/null 2>&1; then echo poetry; return; fi
  if { [ -f pyproject.toml ] || [ -f setup.py ] || [ -f setup.cfg ] || [ -f requirements.txt ]; } \
      && command -v pip >/dev/null 2>&1; then
    echo pip; return
  fi
}
