#!/usr/bin/env bash
set -euo pipefail

errors=0

fail() {
  echo "crossrefs: ERROR: $*"
  errors=$((errors + 1))
}

if [ ! -d .claude/agents ]; then
  fail "missing .claude/agents"
fi
if [ ! -d .claude/skills ]; then
  fail "missing .claude/skills"
fi
if [ ! -d .claude/commands ]; then
  fail "missing .claude/commands"
fi

mapfile -t skill_names < <(rg -n '^name:' .claude/skills/*/SKILL.md -r '$0' 2>/dev/null | sed 's/.*name:[[:space:]]*//' | tr -d '"' | sort -u)
mapfile -t agent_names < <(rg -n '^name:' .claude/agents/*.md -r '$0' 2>/dev/null | sed 's/.*name:[[:space:]]*//' | tr -d '"' | sort -u)

if [ "${#skill_names[@]}" -eq 0 ]; then
  fail "no skills discovered"
fi
if [ "${#agent_names[@]}" -eq 0 ]; then
  fail "no agents discovered"
fi

has_skill() {
  local target="$1"
  printf '%s\n' "${skill_names[@]}" | rg -x -q -- "$target"
}

has_agent() {
  local target="$1"
  printf '%s\n' "${agent_names[@]}" | rg -x -q -- "$target"
}

for agent_file in .claude/agents/*.md; do
  if ! rg -q '^description:' "$agent_file"; then
    fail "$agent_file missing required description"
  fi

  in_skills=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^skills: ]]; then
      in_skills=1
      continue
    fi
    if [ "$in_skills" -eq 1 ]; then
      if [[ "$line" =~ ^---$ ]]; then
        in_skills=0
      elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-zA-Z0-9_-]+) ]]; then
        skill="${BASH_REMATCH[1]}"
        if ! has_skill "$skill"; then
          fail "$agent_file references missing skill '$skill'"
        fi
      elif [[ "$line" =~ ^[a-zA-Z] ]]; then
        in_skills=0
      fi
    fi
  done < "$agent_file"
done

for cmd_file in .claude/commands/*.md; do
  if rg -q '^agent:' "$cmd_file"; then
    agent="$(sed -n 's/^agent:[[:space:]]*//p' "$cmd_file" | head -n1 | tr -d '"')"
    if [ -n "$agent" ] && ! has_agent "$agent"; then
      fail "$cmd_file references missing agent '$agent'"
    fi
  fi

  in_agents=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^agents: ]]; then
      in_agents=1
      continue
    fi
    if [ "$in_agents" -eq 1 ]; then
      if [[ "$line" =~ ^---$ ]]; then
        in_agents=0
      elif [[ "$line" =~ ^[[:space:]]*-[[:space:]]*([a-zA-Z0-9_-]+) ]]; then
        listed_agent="${BASH_REMATCH[1]}"
        if ! has_agent "$listed_agent"; then
          fail "$cmd_file references missing listed agent '$listed_agent'"
        fi
      elif [[ "$line" =~ ^[a-zA-Z] ]]; then
        in_agents=0
      fi
    fi
  done < "$cmd_file"
done

if [ -f CLAUDE.md ]; then
  while IFS= read -r ref; do
    path="${ref#@}"
    if [ ! -f "$path" ]; then
      fail "CLAUDE.md references missing rule '$path'"
    fi
  done < <(rg -n '^@\.claude/rules/.+\.md$' CLAUDE.md -r '$0' | sed 's/^[0-9]*://')
else
  fail "missing CLAUDE.md"
fi

if [ "$errors" -gt 0 ]; then
  echo "crossrefs: FAILED with $errors error(s)"
  exit 1
fi

echo "crossrefs: OK"
