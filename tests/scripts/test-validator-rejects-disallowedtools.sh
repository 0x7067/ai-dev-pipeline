#!/usr/bin/env bash
# Asserts the inline boundary check in scripts/validate-claude-config.sh
# fails non-zero when any .claude/agents/*.md file contains
# '^disallowedTools:'. The validator is sourced verbatim from the repo
# (no copy/duplication); we stage a temporary sandbox that mirrors the
# minimum layout the validator's earlier checks require so that the
# disallowedTools probe is the gate that fires.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "test: SKIP (jq not installed)"
  exit 0
fi

sb="$(mktemp -d)"
trap 'rm -rf "$sb"' EXIT

# Stage a sandbox that mirrors the parts of the repo the validator parses.
# We copy scripts/ wholesale because validate-claude-config.sh delegates to
# several sub-checks; the new disallowedTools probe runs BEFORE those, so it
# fires first when the offending agent file is present.
mkdir -p "$sb/scripts" "$sb/.claude-plugin" "$sb/.claude/agents"
cp -R "$REPO_ROOT/scripts/." "$sb/scripts/"

# Minimal valid plugin.json + marketplace.json with matching versions and
# no hook references (so the hook-existence probe trivially passes).
cat > "$sb/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "sandbox-plugin",
  "version": "9.9.9",
  "description": "sandbox",
  "agents": ["./.claude/agents/offender.md"]
}
EOF
cat > "$sb/.claude-plugin/marketplace.json" <<'EOF'
{
  "name": "sandbox",
  "owner": {"name": "sandbox"},
  "plugins": [
    {"name": "sandbox-plugin", "source": "./", "description": "x", "version": "9.9.9"}
  ]
}
EOF

# CHANGELOG entry so check-plugin-version-sync.sh would pass if it ran.
cat > "$sb/CHANGELOG.md" <<'EOF'
# Changelog

## [9.9.9] - 2026-05-09

- sandbox release.
EOF

# Synthetic agent file with the forbidden field.
cat > "$sb/.claude/agents/offender.md" <<'EOF'
---
name: offender
description: sandbox agent that violates the allowlist-only convention
tools: ["Read"]
disallowedTools: ["Bash"]
---

body
EOF

# Run validator from sandbox; capture rc and stderr.
out_err="$(cd "$sb" && bash scripts/validate-claude-config.sh 2>&1 >/dev/null)"
rc=$?

if [ "$rc" -ne 0 ]; then
  pass "validator exits non-zero when disallowedTools: present (rc=$rc)"
else
  fail "validator exited 0 but disallowedTools: should be rejected"
fi

if printf '%s\n' "$out_err" | grep -qi 'disallowedTools'; then
  pass "validator stderr mentions 'disallowedTools'"
else
  fail "validator stderr did not mention 'disallowedTools'; got: $out_err"
fi

# Round-trip: removing the offending line flips the gate. We rewrite the
# agent file without the disallowedTools: line and assert the validator no
# longer fails on THIS check (it may still fail on later sub-checks, which
# is fine — the assertion is that the disallowedTools error is gone).
cat > "$sb/.claude/agents/offender.md" <<'EOF'
---
name: offender
description: sandbox agent that now follows the allowlist-only convention
tools: ["Read"]
---

body
EOF

clean_err="$(cd "$sb" && bash scripts/validate-claude-config.sh 2>&1 >/dev/null || true)"
if printf '%s\n' "$clean_err" | grep -qi "ERROR: agent file(s) declare 'disallowedTools:'"; then
  fail "validator still reports disallowedTools after the line was removed"
else
  pass "removing disallowedTools: line clears the gate"
fi

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
printf '\nall assertions passed\n'
