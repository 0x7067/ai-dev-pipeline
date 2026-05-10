#!/usr/bin/env bash
# Validator test: scripts/validate-claude-config.sh enforces the
# Open-Decisions ⇔ AskUserQuestion pairing AND the prose-halt ⇔
# AskUserQuestion pairing in command files.
#
# Strategy: synthesize a sandbox repo with a minimal .claude tree containing
# fixture .md files, then run the validator inside it and assert the relevant
# pairing-violation lines appear (or do not appear) on stderr.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
VALIDATOR="${REPO_ROOT}/scripts/validate-claude-config.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$VALIDATOR" ] || { echo "validator missing at $VALIDATOR" >&2; exit 2; }

# Build a minimal sandbox once; the agents/commands subdirs get rewritten per case.
make_sandbox() {
  local sandbox="$1"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/.claude/agents" "$sandbox/.claude/commands" \
           "$sandbox/.claude/skills" "$sandbox/.claude/hooks" \
           "$sandbox/.claude-plugin" "$sandbox/scripts"
  # Minimal plugin manifest the validator can parse.
  cat > "$sandbox/.claude-plugin/plugin.json" <<'EOF'
{ "name": "fixture", "version": "0.0.1", "description": "fixture" }
EOF
  # Symlink scripts so the validator's sub-checks can resolve.
  ln -sf "${REPO_ROOT}/scripts" "$sandbox/scripts.real"
  # Copy only what the validator's sub-checks call.
  for s in harness-lib.sh check-crossrefs.sh check-boundary-violations.sh \
           check-plugin-version-sync.sh check-skill-triggers.sh check-write-allowed.sh \
           validate-claude-config.sh; do
    cp "${REPO_ROOT}/scripts/$s" "$sandbox/scripts/$s" 2>/dev/null || true
  done
  mkdir -p "$sandbox/scripts/lib"
  cp -R "${REPO_ROOT}/scripts/lib/." "$sandbox/scripts/lib/" 2>/dev/null || true
}

# Run validator in sandbox; capture combined stderr.
run_validator() {
  local sandbox="$1"
  ( cd "$sandbox" && bash scripts/validate-claude-config.sh 2>&1 )
}

sandbox="$(mktemp -d -t validator-pairing.XXXXXX)"
trap 'rm -rf "$sandbox"' EXIT

# ---------- Case 1: passing fixture (Open Decisions + AskUserQuestion) ----------
make_sandbox "$sandbox"
cat > "$sandbox/.claude/agents/passing-agent.md" <<'EOF'
---
name: passing-agent
description: fixture
tools: 'Read, AskUserQuestion'
---

## Open Decisions (provisional)

These will be confirmed at the plan gate via AskUserQuestion.

```
AskUserQuestion:
  question: "Pick X?"
  options:
    - label: "A (Recommended)"
      description: do A
    - label: "B"
      description: do B
```
EOF
out=$(run_validator "$sandbox")
if printf '%s' "$out" | grep -q 'pairing violation'; then
  fail "passing fixture should not trigger pairing violations: $out"
else
  pass "passing fixture passes pairing checks"
fi

# ---------- Case 2: missing-askuserquestion fixture ----------
make_sandbox "$sandbox"
cat > "$sandbox/.claude/agents/missing-auq.md" <<'EOF'
---
name: missing-auq
description: fixture
---

## Open Decisions

There are some open decisions but no pairing tool reference here.
EOF
out=$(run_validator "$sandbox")
if printf '%s' "$out" | grep -q 'Open Decisions section without AskUserQuestion pairing'; then
  pass "missing AskUserQuestion triggers pairing violation"
else
  fail "missing AskUserQuestion: expected violation message; got: $out"
fi

# ---------- Case 3: prose-halt fixture (command file without AskUserQuestion) ----------
make_sandbox "$sandbox"
cat > "$sandbox/.claude/commands/prose-halt.md" <<'EOF'
---
description: fixture
---

Halt and reply "approve" to continue, or reply "reject" to stop.
EOF
out=$(run_validator "$sandbox")
if printf '%s' "$out" | grep -q 'prose halt template without AskUserQuestion pairing'; then
  pass "prose halt without AskUserQuestion triggers pairing violation"
else
  fail "prose halt: expected violation message; got: $out"
fi

if [ "$failures" -eq 0 ]; then
  echo "open-decisions-pairing: PASS"
  exit 0
fi
echo "open-decisions-pairing: FAIL ($failures)" >&2
exit 1
