#!/usr/bin/env bash
# Contract tests for scripts/release/parse-changelog.sh.
#
# Accept set: well-formed Keep-a-Changelog 1.1.0 fragments parse and emit
# the expected typed records. Reject set: malformed inputs fail closed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$REPO_ROOT/scripts/release/parse-changelog.sh"
# shellcheck source=scripts/release/lib/changelog-core.sh
source "$REPO_ROOT/scripts/release/lib/changelog-core.sh"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

tmp="$(mktemp -d -t changelog-tests.XXXXXX)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# --- Accept set --------------------------------------------------------------
cat > "$tmp/ok-unreleased.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- New release skill at `.claude/skills/release/SKILL.md`.

### Fixed

- Tag body no longer includes empty lines.

## [0.15.1] - 2026-05-10

### Changed

- Persistent feature specs moved.
EOF

if records="$("$PARSER" "$tmp/ok-unreleased.md")"; then
  pass "accept: topmost Unreleased parses"
  if grep -qx 'section_label	Unreleased' <<<"$records"; then
    pass "accept: emits section_label Unreleased"
  else
    fail "accept: missing section_label Unreleased record"
  fi
  bump="$(printf '%s\n' "$records" | infer_bump_from_changelog)"
  if [[ "$bump" == "minor" ]]; then
    pass "infer_bump: Added+Fixed -> minor"
  else
    fail "infer_bump: expected minor, got $bump"
  fi
else
  fail "accept: topmost Unreleased rejected"
fi

cat > "$tmp/ok-patch.md" <<'EOF'
# Changelog

## [Unreleased]

### Fixed

- Off-by-one in the parser.
EOF

bump="$("$PARSER" "$tmp/ok-patch.md" | infer_bump_from_changelog)"
[[ "$bump" == "patch" ]] && pass "infer_bump: Fixed-only -> patch" || fail "Fixed-only -> $bump"

cat > "$tmp/ok-major.md" <<'EOF'
# Changelog

## [Unreleased]

### Removed

- Deprecated /spdd-* commands.
EOF

bump="$("$PARSER" "$tmp/ok-major.md" | infer_bump_from_changelog)"
[[ "$bump" == "major" ]] && pass "infer_bump: Removed -> major" || fail "Removed -> $bump"

cat > "$tmp/ok-breaking-tag.md" <<'EOF'
# Changelog

## [Unreleased]

### Changed

- [BREAKING] Renamed env var.
EOF

bump="$("$PARSER" "$tmp/ok-breaking-tag.md" | infer_bump_from_changelog)"
[[ "$bump" == "major" ]] && pass "infer_bump: [BREAKING] tag -> major" || fail "[BREAKING] -> $bump"

# --label mode
label="$("$PARSER" --label "$tmp/ok-unreleased.md")"
[[ "$label" == "Unreleased" ]] && pass "--label prints Unreleased" || fail "--label got '$label'"

# --check mode
"$PARSER" --check "$tmp/ok-unreleased.md" && pass "--check returns 0 on valid" || fail "--check returned non-zero on valid"

# --- Reject set --------------------------------------------------------------
cat > "$tmp/bad-no-bracket.md" <<'EOF'
# Changelog

## [Unreleased

### Added
- foo
EOF
"$PARSER" --check "$tmp/bad-no-bracket.md" 2>/dev/null && fail "reject: malformed header (no bracket) accepted" || pass "reject: malformed header (no bracket)"

cat > "$tmp/bad-unknown-label.md" <<'EOF'
# Changelog

## [Unreleased]

### Frobbed

- shouldn't be allowed
EOF
"$PARSER" "$tmp/bad-unknown-label.md" >/dev/null 2>&1 && fail "reject: unknown subsection label accepted" || pass "reject: unknown subsection label '### Frobbed'"

cat > "$tmp/bad-no-date.md" <<'EOF'
# Changelog

## [1.2.3]

### Added
- foo
EOF
"$PARSER" --check "$tmp/bad-no-date.md" 2>/dev/null && fail "reject: missing date accepted" || pass "reject: versioned section missing date"

cat > "$tmp/bad-bad-date.md" <<'EOF'
# Changelog

## [1.2.3] - 2026/05/10

### Added
- foo
EOF
"$PARSER" --check "$tmp/bad-bad-date.md" 2>/dev/null && fail "reject: malformed date accepted" || pass "reject: malformed date"

cat > "$tmp/bad-bad-version.md" <<'EOF'
# Changelog

## [v1.2.3] - 2026-05-10

### Added
- foo
EOF
"$PARSER" --check "$tmp/bad-bad-version.md" 2>/dev/null && fail "reject: 'v'-prefixed version accepted" || pass "reject: v-prefixed version"

cat > "$tmp/bad-duplicate.md" <<'EOF'
# Changelog

## [1.2.3] - 2026-05-09

### Added
- foo

## [1.2.3] - 2026-05-10

### Added
- bar
EOF
"$PARSER" --all "$tmp/bad-duplicate.md" >/dev/null 2>&1 && fail "reject: duplicate version (--all) accepted" || pass "reject: duplicate version under --all"

cat > "$tmp/bad-bullet-no-section.md" <<'EOF'
# Changelog

## [Unreleased]

- bullet without a ### heading
EOF
"$PARSER" "$tmp/bad-bullet-no-section.md" >/dev/null 2>&1 && fail "reject: bullet with no '###' subsection accepted" || pass "reject: bullet outside subsection"

if (( fail_count > 0 )); then
  printf '\nFAILED (%d failure(s))\n' "$fail_count" >&2
  exit 1
fi
echo "OK"
