#!/usr/bin/env bash
set -euo pipefail

errors=0
skill_names=()
agent_names=()

fail() {
  echo "crossrefs: ERROR: $*"
  errors=$((errors + 1))
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

file_has_pattern() {
  local pattern="$1"
  local file="$2"

  if has_rg; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

collect_name_fields() {
  local path_glob="$1"

  if has_rg; then
    rg --no-filename '^name:' $path_glob 2>/dev/null |
      sed 's/^name:[[:space:]]*//' |
      tr -d '"' |
      sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
      awk 'NF' |
      sort -u
  else
    grep -h -E '^name:' $path_glob 2>/dev/null |
      sed 's/^name:[[:space:]]*//' |
      tr -d '"' |
      sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
      awk 'NF' |
      sort -u
  fi
}

load_names() {
  local target_array_name="$1"
  local path_glob="$2"
  local line

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    eval "$target_array_name+=(\"\$line\")"
  done < <(collect_name_fields "$path_glob")
}

has_skill() {
  local target="$1"
  local name

  for name in "${skill_names[@]}"; do
    if [ "$name" = "$target" ]; then
      return 0
    fi
  done

  return 1
}

has_agent() {
  local target="$1"
  local name

  for name in "${agent_names[@]}"; do
    if [ "$name" = "$target" ]; then
      return 0
    fi
  done

  return 1
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

load_names skill_names ".claude/skills/*/SKILL.md"
load_names agent_names ".claude/agents/*.md"

if [ "${#skill_names[@]}" -eq 0 ]; then
  fail "no skills discovered"
fi
if [ "${#agent_names[@]}" -eq 0 ]; then
  fail "no agents discovered"
fi

for agent_file in .claude/agents/*.md; do
  if ! file_has_pattern '^description:' "$agent_file"; then
    fail "$agent_file missing required description"
  fi

  in_skills=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^skills:[[:space:]]*(.*)$ ]]; then
      raw_skills="${BASH_REMATCH[1]}"
      raw_skills="${raw_skills//\"/}"
      raw_skills="${raw_skills//\'/}"
      if [ -n "$raw_skills" ]; then
        IFS=',' read -ra skill_items <<< "$raw_skills"
        for skill_item in "${skill_items[@]}"; do
          skill="$(printf '%s' "$skill_item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
          [ -n "$skill" ] || continue
          if ! has_skill "$skill"; then
            fail "$agent_file references missing skill '$skill'"
          fi
        done
        in_skills=0
      else
        in_skills=1
      fi
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
  if file_has_pattern '^agent:' "$cmd_file"; then
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
  done < <(
    if has_rg; then
      rg --no-filename '^@\.claude/rules/.+\.md$' CLAUDE.md 2>/dev/null
    else
      grep -E '^@\.claude/rules/.+\.md$' CLAUDE.md 2>/dev/null
    fi
  )
else
  fail "missing CLAUDE.md"
fi

if [ "$errors" -gt 0 ]; then
  echo "crossrefs: FAILED with $errors error(s)"
  exit 1
fi

echo "crossrefs: OK"
