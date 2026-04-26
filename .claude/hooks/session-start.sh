#!/usr/bin/env bash
# SessionStart hook for ai-dev-pipeline plugin.
# Injects the using-pipeline meta-skill as additionalContext so Claude
# proactively engages pipeline skills before responding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"

SKILL_PATH="${PLUGIN_ROOT}/.claude/skills/using-pipeline/SKILL.md"

using_pipeline_content=$(cat "${SKILL_PATH}" 2>&1 || echo "Error reading using-pipeline skill")

# JSON-escape via bash parameter substitution (single-pass per replacement).
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

using_pipeline_escaped=$(escape_for_json "$using_pipeline_content")

session_context="<EXTREMELY_IMPORTANT>\nThis repository uses the ai-dev-pipeline workflow. You must engage pipeline skills proactively rather than waiting for explicit slash commands.\n\n**Below is the full content of the 'using-pipeline' meta-skill — your introduction to the pipeline. For all other skills, use the 'Skill' tool:**\n\n${using_pipeline_escaped}\n</EXTREMELY_IMPORTANT>"

# Claude Code expects hookSpecificOutput.additionalContext.
# printf is used instead of heredoc to avoid bash 5.3+ heredoc hangs
# (see https://github.com/obra/superpowers/issues/571).
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n    "additionalContext": "%s"\n  }\n}\n' "$session_context"

exit 0
