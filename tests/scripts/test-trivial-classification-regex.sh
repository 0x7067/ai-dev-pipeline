#!/usr/bin/env bash
# Contract test: trivial-skip path classification heuristic.
#
# Per docs/current-plan.md "Resolved Decisions" #1 and
# .claude/commands/ship.md step 4, the orchestrator skips TDD when the
# plan is classified `trivial`. The primary signal is the front-matter
# token `change-type: trivial` in docs/current-plan.md.
#
# This test simulates a plan with that front-matter and asserts that
# the classification heuristic — a pure-shell regex — matches it.
# It also covers negative cases (feature, bugfix, missing) and a
# whitespace-tolerance positive case.
#
# Pure shell parsing only. The orchestrator is not invoked.

set -uo pipefail

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Pure shell classifier: returns 0 if the plan's front-matter declares
# change-type: trivial, 1 otherwise. Front-matter is the leading
# block delimited by `---` lines.
classify_trivial() {
  local plan_path="$1"
  [ -f "$plan_path" ] || return 1
  # Extract front-matter (lines between the first two `---` lines).
  awk '
    BEGIN { in_fm=0; seen=0 }
    /^---[[:space:]]*$/ {
      if (seen==0) { in_fm=1; seen=1; next }
      else if (in_fm==1) { exit }
    }
    in_fm==1 { print }
  ' "$plan_path" | grep -qE '^[[:space:]]*change-type:[[:space:]]*trivial[[:space:]]*$'
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Case 1: trivial plan -> classified trivial.
cat >"$tmpdir/plan-trivial.md" <<'EOF'
---
change-type: trivial
risk: low
---

# Plan: typo fix
EOF
if classify_trivial "$tmpdir/plan-trivial.md"; then
  pass "change-type: trivial classified as trivial"
else
  fail "change-type: trivial NOT classified as trivial"
fi

# Case 2: feature plan -> NOT trivial.
cat >"$tmpdir/plan-feature.md" <<'EOF'
---
change-type: feature
risk: medium
---

# Plan: add a thing
EOF
if classify_trivial "$tmpdir/plan-feature.md"; then
  fail "change-type: feature wrongly classified as trivial"
else
  pass "change-type: feature NOT trivial"
fi

# Case 3: bugfix plan -> NOT trivial.
cat >"$tmpdir/plan-bugfix.md" <<'EOF'
---
change-type: bugfix
risk: low
---

# Plan: fix a thing
EOF
if classify_trivial "$tmpdir/plan-bugfix.md"; then
  fail "change-type: bugfix wrongly classified as trivial"
else
  pass "change-type: bugfix NOT trivial"
fi

# Case 4: missing front-matter -> NOT trivial (fail closed).
cat >"$tmpdir/plan-no-fm.md" <<'EOF'
# Plan: no front-matter
just text.
EOF
if classify_trivial "$tmpdir/plan-no-fm.md"; then
  fail "missing front-matter wrongly classified as trivial"
else
  pass "missing front-matter NOT trivial (fail closed)"
fi

# Case 5: whitespace-tolerance — extra spaces around the value.
cat >"$tmpdir/plan-trivial-ws.md" <<'EOF'
---
change-type:   trivial
risk: low
---

# Plan: comment-only change
EOF
if classify_trivial "$tmpdir/plan-trivial-ws.md"; then
  pass "whitespace-tolerant trivial classification"
else
  fail "whitespace around value broke trivial classification"
fi

# Case 6: substring saboteur — `change-type: nontrivial` MUST NOT match.
cat >"$tmpdir/plan-nontrivial.md" <<'EOF'
---
change-type: nontrivial
risk: medium
---

# Plan: not a trivial change
EOF
if classify_trivial "$tmpdir/plan-nontrivial.md"; then
  fail "substring 'nontrivial' wrongly classified as trivial"
else
  pass "substring saboteur 'nontrivial' rejected"
fi

# Case 7: token must be inside the front-matter block, not in the body.
cat >"$tmpdir/plan-body-mention.md" <<'EOF'
---
change-type: feature
risk: medium
---

# Plan
This plan considers `change-type: trivial` cases in the description.
EOF
if classify_trivial "$tmpdir/plan-body-mention.md"; then
  fail "body mention of 'change-type: trivial' wrongly classified as trivial"
else
  pass "body-only mention rejected (front-matter-scoped)"
fi

if [ "$failures" -eq 0 ]; then
  echo "trivial-classification-regex: ok"
  exit 0
fi
echo "trivial-classification-regex: $failures failure(s)" >&2
exit 1
