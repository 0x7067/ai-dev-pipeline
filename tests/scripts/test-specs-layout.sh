#!/usr/bin/env bash
# Layout/contract tests for the new docs/specs/ structure.
#
# Asserts:
#   - Each known spec lives under docs/specs/<id>/spec.yaml (D3).
#   - docs/specs/index.yaml exists and parses (INV-2 via parse-spec.sh --index).
#   - docs/artifacts/specs/ no longer exists (INV-6, D4).
#   - .gitignore tracks docs/specs/_site/ (INV-1, INV-7).
#   - Renderer is idempotent: two consecutive runs produce byte-identical
#     output (INV-4).
#   - Renderer exits 0 on the migrated tree.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PARSER="$REPO_ROOT/scripts/specs/parse-spec.sh"
RENDERER="$REPO_ROOT/scripts/specs/render-html.sh"

fail_count=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fail_count=$((fail_count + 1)); }

# Per-spec layout.
for id in zero-setup-install decision-surfacing run-id-isolation; do
  if [[ -f "$REPO_ROOT/docs/specs/$id/spec.yaml" ]]; then
    pass "docs/specs/$id/spec.yaml exists"
  else
    fail "docs/specs/$id/spec.yaml missing"
  fi
done

# Old flat layout removed.
for id in zero-setup-install decision-surfacing run-id-isolation; do
  if [[ -e "$REPO_ROOT/docs/specs/$id.md" ]]; then
    fail "legacy flat file still present: docs/specs/$id.md"
  else
    pass "legacy flat file removed: docs/specs/$id.md"
  fi
done

# Index file.
if [[ -f "$REPO_ROOT/docs/specs/index.yaml" ]]; then
  pass "docs/specs/index.yaml exists"
  if "$PARSER" --index "$REPO_ROOT/docs/specs/index.yaml" >/dev/null 2>&1; then
    pass "index.yaml parses"
  else
    fail "index.yaml does not parse"
  fi
else
  fail "docs/specs/index.yaml missing"
fi

# Orphan mirror gone (INV-6, D4).
if [[ -d "$REPO_ROOT/docs/artifacts/specs" ]]; then
  fail "docs/artifacts/specs/ still exists (INV-6 violated)"
else
  pass "docs/artifacts/specs/ removed (INV-6)"
fi

# .gitignore entry for _site/.
if grep -qE '^docs/specs/_site/?$' "$REPO_ROOT/.gitignore"; then
  pass ".gitignore tracks docs/specs/_site/"
else
  fail ".gitignore is missing entry for docs/specs/_site/"
fi

# Renderer idempotence (INV-4).
if [[ -x "$RENDERER" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  if bash "$RENDERER" >/dev/null 2>&1; then
    cp -R "$REPO_ROOT/docs/specs/_site" "$TMP/site-a"
    if bash "$RENDERER" >/dev/null 2>&1; then
      if diff -r "$TMP/site-a" "$REPO_ROOT/docs/specs/_site" >/dev/null 2>&1; then
        pass "renderer is byte-idempotent (INV-4)"
      else
        fail "renderer output differs across runs (INV-4)"
      fi
    else
      fail "renderer second invocation failed"
    fi
  else
    fail "renderer first invocation failed"
  fi
else
  fail "renderer not executable: $RENDERER"
fi

if [[ "$fail_count" -gt 0 ]]; then
  printf '\n%d assertion(s) failed\n' "$fail_count" >&2
  exit 1
fi
printf '\nall assertions passed\n'
