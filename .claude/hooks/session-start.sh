#!/usr/bin/env bash
# SessionStart hook for ai-dev-pipeline plugin.
# Injects the using-pipeline meta-skill as additionalContext so Claude
# proactively engages pipeline skills before responding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

SKILL_PATH="${PLUGIN_ROOT}/.claude/skills/using-pipeline/SKILL.md"

if [ ! -f "${SKILL_PATH}" ]; then
  printf 'session-start: ERROR: using-pipeline SKILL.md not found at %s\n' "${SKILL_PATH}" >&2
  exit 1
fi
using_pipeline_content=$(cat "${SKILL_PATH}")

# JSON-escape: prefer jq (handles all Unicode + control chars correctly).
# Fallback: bash parameter substitution covering the common cases plus
# U+0001-U+001F control chars encoded as \uXXXX.
escape_for_json() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -Rs '.[0:-1]'
        return
    fi
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    # Encode remaining C0 control chars (U+0001..U+0008, U+000B, U+000C, U+000E..U+001F).
    local i
    for i in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
        local ctrl
        ctrl="$(printf "\\$(printf '%03o' "$i")")"
        local hex
        hex="$(printf '%04x' "$i")"
        s="${s//${ctrl}/\\u${hex}}"
    done
    printf '%s' "$s"
}

using_pipeline_escaped=$(escape_for_json "$using_pipeline_content")

session_context="<EXTREMELY_IMPORTANT>\nThis repository uses the ai-dev-pipeline workflow. You must engage pipeline skills proactively rather than waiting for explicit slash commands.\n\n**Below is the full content of the 'using-pipeline' meta-skill — your introduction to the pipeline. For all other skills, use the 'Skill' tool:**\n\n${using_pipeline_escaped}\n</EXTREMELY_IMPORTANT>"

# Claude Code expects hookSpecificOutput.additionalContext.
# printf is used instead of heredoc to avoid bash 5.3+ heredoc hangs
# (see https://github.com/obra/superpowers/issues/571).
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$session_context"

exit 0
