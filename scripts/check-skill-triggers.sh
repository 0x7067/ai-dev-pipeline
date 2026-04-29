#!/usr/bin/env bash
set -uo pipefail

# Validates that each .claude/skills/*/skill.md has a `description:` field with
# enough trigger signal for Claude to reliably auto-invoke. Required signals:
#   - description is at least MIN_LEN chars
#   - mentions a trigger context: a slash command (e.g. `/review`),
#     "Trigger on", "Invoked by", "Use when", "Triggers on", or "do not invoke"
# Failures are reported but not blocking (exit 0) unless STRICT=1.

MIN_LEN="${SKILL_DESC_MIN_LEN:-80}"
STRICT="${STRICT:-0}"

if ! command -v rg >/dev/null 2>&1 && ! command -v grep >/dev/null 2>&1; then
  echo "check-skill-triggers: ERROR: rg or grep required" >&2
  exit 1
fi

shopt -s nullglob
skills=(.claude/skills/*/skill.md)
if [ "${#skills[@]}" -eq 0 ]; then
  echo "check-skill-triggers: skipped (no skills found under .claude/skills/)"
  exit 0
fi

errors=0
warnings=0

for f in "${skills[@]}"; do
  desc="$(awk '/^---$/{n++; next} n==1 && /^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$f")"

  if [ -z "$desc" ]; then
    echo "check-skill-triggers: ERROR: $f missing 'description:' frontmatter field" >&2
    errors=$((errors + 1))
    continue
  fi

  if [ "${#desc}" -lt "$MIN_LEN" ]; then
    echo "check-skill-triggers: WARN: $f description is short (${#desc} < $MIN_LEN chars) — add a trigger context and a do-not-invoke guard" >&2
    warnings=$((warnings + 1))
  fi

  if ! printf '%s' "$desc" | grep -Eqi '/[a-z][a-z-]+|trigger on|invoked by|use when|triggers on|do not invoke'; then
    echo "check-skill-triggers: WARN: $f description has no clear trigger signal (expected '/command', 'Trigger on', 'Invoked by', 'Use when', or 'Do not invoke')" >&2
    warnings=$((warnings + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "check-skill-triggers: FAILED ($errors errors, $warnings warnings)" >&2
  exit 1
fi

if [ "$warnings" -gt 0 ]; then
  if [ "$STRICT" = "1" ]; then
    echo "check-skill-triggers: STRICT mode — failing on $warnings warning(s)" >&2
    exit 1
  fi
  echo "check-skill-triggers: OK ($warnings advisory warning(s) — set STRICT=1 to block)"
  exit 0
fi

echo "check-skill-triggers: OK (${#skills[@]} skill(s) checked)"
