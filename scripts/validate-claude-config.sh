#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
# shellcheck source=scripts/lib/style.sh
source "${SCRIPT_DIR}/lib/style.sh"
harness_cd_repo_root

if ! command -v jq >/dev/null 2>&1; then
  echo "validate: ERROR: jq is required" >&2
  echo "validate: install jq (e.g. 'brew install jq' or 'apt-get install jq') and retry" >&2
  exit 1
fi

plugin_manifest=".claude-plugin/plugin.json"

if [ ! -f "$plugin_manifest" ]; then
  echo "validate: ERROR: missing $plugin_manifest" >&2
  exit 1
fi

if ! jq empty "$plugin_manifest" >/dev/null 2>&1; then
  echo "validate: ERROR: $plugin_manifest is not valid JSON" >&2
  exit 1
fi

# Boundary check: forbid .claude/settings.json from re-declaring hook entries
# already owned by .claude-plugin/plugin.json. The plugin manifest is the
# single source of truth; settings.json hook entries are CWD-relative and
# silently break when the plugin is consumed from any other repo.
if [ -f .claude/settings.json ]; then
  if ! jq empty .claude/settings.json >/dev/null 2>&1; then
    echo "validate: ERROR: .claude/settings.json is not valid JSON" >&2
    exit 1
  fi
  settings_hook_count="$(jq '[.hooks // {} | to_entries[] | .value[]?.hooks[]?] | length' .claude/settings.json 2>/dev/null || echo 0)"
  if [ "${settings_hook_count:-0}" -gt 0 ]; then
    echo "validate: ERROR: .claude/settings.json declares $settings_hook_count hook entries" >&2
    echo "validate: hook registration is owned by $plugin_manifest; remove the 'hooks' block from .claude/settings.json (or delete the file if it has no other content)" >&2
    exit 1
  fi
fi

# Boundary check: every hook script referenced by plugin.json must exist on disk.
missing_hooks="$(jq -r '
  [.hooks // {} | to_entries[] | .value[]?.hooks[]?.command]
  | map(capture("\\$\\{CLAUDE_PLUGIN_ROOT\\}/(?<p>\\S+)") | .p)
  | .[]
' "$plugin_manifest" 2>/dev/null | while read -r relpath; do
  [ -z "$relpath" ] && continue
  if [ ! -f "$relpath" ]; then
    echo "$relpath"
  fi
done)"

if [ -n "$missing_hooks" ]; then
  echo "validate: ERROR: $plugin_manifest references missing hook scripts:" >&2
  while IFS= read -r p; do
    echo "  - $p" >&2
  done <<< "$missing_hooks"
  exit 1
fi

echo "validate: plugin.json hook references resolve and settings.json does not duplicate hooks"

# Boundary check: allowlist-only convention from
# .claude/rules/security-baseline.md — no agent file may declare a
# 'disallowedTools:' field. Permissions must be expressed as an explicit
# 'tools:' allowlist.
if ls .claude/agents/*.md >/dev/null 2>&1; then
  disallowed_hits="$(grep -l '^disallowedTools:' .claude/agents/*.md 2>/dev/null || true)"
  if [ -n "$disallowed_hits" ]; then
    echo "validate: ERROR: agent file(s) declare 'disallowedTools:' (forbidden by .claude/rules/security-baseline.md allowlist-only convention):" >&2
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      echo "  - $f" >&2
    done <<< "$disallowed_hits"
    exit 1
  fi
fi

# Boundary check: decision-surfacing pairing rules (per
# .claude/rules/decision-surfacing.md). Two sub-checks, both pure bash:
#   (a) Agent files with an "## Open Decisions" heading must mention
#       AskUserQuestion somewhere in the same file.
#   (b) Command files containing prose halts (`reply "approve"` or
#       `reply "reject"`) must also reference AskUserQuestion in the same
#       file (relaxed proximity check).
_decision_pairing_violations=0
_emit_pair_err() {
  # bash emitter uses style::fail; awk printf calls in _check_norms_block
  # remain plain (awk runs in a subshell without access to bash functions).
  style::fail "validate: $1" >&2
  _decision_pairing_violations=$((_decision_pairing_violations + 1))
}

# (a) Open Decisions ⇔ AskUserQuestion (agent files only).
if ls .claude/agents/*.md >/dev/null 2>&1; then
  for f in .claude/agents/*.md; do
    [ -f "$f" ] || continue
    # Heading match: ^##\s+Open Decisions, case-insensitive, optional trailing parenthetical.
    if grep -Eiq '^##[[:space:]]+Open Decisions([[:space:]]*\(.*\))?[[:space:]]*$' "$f"; then
      if ! grep -q 'AskUserQuestion' "$f"; then
        _emit_pair_err "${f}: Open Decisions section without AskUserQuestion pairing"
      fi
    fi
  done
fi

# (b) Prose halt patterns (reply "approve"/"reject") in command files require AskUserQuestion in same file.
for f in .claude/commands/*.md; do
  [ -f "$f" ] || continue
  if grep -Eq 'reply "(approve|reject)"' "$f"; then
    if ! grep -q 'AskUserQuestion' "$f"; then
      _emit_pair_err "${f}: prose halt template without AskUserQuestion pairing"
    fi
  fi
done

if [ "$_decision_pairing_violations" -gt 0 ]; then
  echo "validate: ERROR: $_decision_pairing_violations decision-surfacing pairing violation(s)" >&2
  exit 1
fi

# Boundary check: Norms/Safeguards content style (invariant I3 of the
# SPDD-borrows plan). When a plan or plan template contains a
# `## Norms applied` or `## Safeguards applied` section, every non-empty,
# non-comment, non-bullet-marker line in that section must reference a
# `.claude/rules/<name>.md` file path. Rule prose, paraphrases, or
# arbitrary commentary are forbidden — links only. Enforced inline so
# there is no extra script dependency.
_norms_violations=0
_check_norms_block() {
  local file="$1"
  awk -v file="$file" '
    BEGIN { in_block = 0; in_comment = 0; bad = 0 }
    /^##[[:space:]]+/ {
      if ($0 ~ /^##[[:space:]]+(Norms applied|Safeguards applied)[[:space:]]*$/) {
        in_block = 1; next
      } else {
        in_block = 0
      }
    }
    in_block {
      raw = $0
      # Track multi-line HTML comments. A line that opens a comment
      # without closing it on the same line enters a comment region;
      # subsequent lines stay skipped until `-->` is seen.
      if (in_comment) {
        if (raw ~ /-->/) in_comment = 0
        next
      }
      if (raw ~ /<!--/ && raw !~ /-->/) {
        in_comment = 1
        next
      }
      # Single-line comment fully on one line.
      if (raw ~ /^[[:space:]]*<!--.*-->[[:space:]]*$/) next
      line = raw
      # Strip leading whitespace and bullet markers (-, *, +, digits.).
      sub(/^[[:space:]]*([-*+]|[0-9]+\.)?[[:space:]]*/, "", line)
      # Skip empty lines.
      if (line ~ /^[[:space:]]*$/) next
      # Accept: line contains a `.claude/rules/<name>.md` path AND no
      # other non-whitespace text outside that path/markdown link wrapper.
      # Permitted shapes:
      #   .claude/rules/foo.md
      #   `.claude/rules/foo.md`
      #   [.claude/rules/foo.md](.claude/rules/foo.md)
      #   [foo](.claude/rules/foo.md)   <-- still link-only, accepted
      # Forbid paraphrases by requiring the line to match one of these
      # link-only shapes end-to-end after stripping wrapping punctuation.
      stripped = line
      # Remove backticks.
      gsub(/`/, "", stripped)
      # If it is a markdown link [text](path), accept iff path is a rules path.
      if (match(stripped, /^\[[^]]*\]\([^)]+\)[[:space:]]*$/)) {
        # Extract the URL portion.
        url = stripped
        sub(/^\[[^]]*\]\(/, "", url)
        sub(/\)[[:space:]]*$/, "", url)
        if (url ~ /^\.claude\/rules\/[a-zA-Z0-9_-]+\.md$/) next
        printf "validate: ✗ %s: Norms/Safeguards link target not a .claude/rules path: %s\n", file, line > "/dev/stderr"
        bad++
        next
      }
      # Otherwise require the entire trimmed line to be a bare rules path.
      sub(/^[[:space:]]+/, "", stripped)
      sub(/[[:space:]]+$/, "", stripped)
      if (stripped ~ /^\.claude\/rules\/[a-zA-Z0-9_-]+\.md$/) next
      printf "validate: ✗ %s: Norms/Safeguards section contains non-link text: %s\n", file, line > "/dev/stderr"
      bad++
    }
    END { exit (bad > 0 ? 1 : 0) }
  ' "$file"
}

# Files to scan: the plan template + every current-plan.md under docs/aidp/runs.
_norms_targets=()
[ -f docs/templates/current-plan-template.md ] && _norms_targets+=(docs/templates/current-plan-template.md)
if [ -d docs/aidp/runs ]; then
  while IFS= read -r f; do
    [ -n "$f" ] && _norms_targets+=("$f")
  done < <(find docs/aidp/runs -type f -name 'current-plan.md' 2>/dev/null)
fi

for f in "${_norms_targets[@]:-}"; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  if ! _check_norms_block "$f"; then
    _norms_violations=$((_norms_violations + 1))
  fi
done

if [ "$_norms_violations" -gt 0 ]; then
  echo "validate: ERROR: $_norms_violations file(s) contain non-link text in Norms/Safeguards section (invariant I3)" >&2
  exit 1
fi

# Advisory: warn if .claude/discovered-patterns/ exists but is not gitignored.
# (Pattern files are ephemeral scan output — not intended for commit.)
if [ -d ".claude/discovered-patterns" ]; then
  _gi_check=0
  # git check-ignore exits 0 if the path is ignored, 1 if not, 128 on error
  git check-ignore -q ".claude/discovered-patterns" 2>/dev/null && _gi_check=1
  if [ "$_gi_check" -eq 0 ]; then
    style::warn "validate: advisory: .claude/discovered-patterns/ exists but is not gitignored"
    style::warn "  add '.claude/discovered-patterns/' to .gitignore to keep ephemeral scan output out of version control"
  fi
fi

rc=0
bash scripts/check-crossrefs.sh             || rc=1
bash scripts/check-boundary-violations.sh   || rc=1
bash scripts/check-plugin-version-sync.sh   || rc=1
bash scripts/check-skill-triggers.sh        || rc=1
bash scripts/check-write-allowed.sh         || rc=1
bash scripts/tests/test-project-root.sh     || rc=1

if [ "$rc" -ne 0 ]; then
  echo "validate: FAILED — one or more sub-checks reported errors above" >&2
  exit 1
fi

echo "validate: OK"
