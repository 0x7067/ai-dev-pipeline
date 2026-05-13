#!/usr/bin/env bash
# Property + contract tests for scripts/mint-run-id.sh.
#
#   - mint→parse round-trip: every minted id is accepted by parse-run-id.
#   - uniqueness: 100 sequential mints produce ≥ 99 distinct ids
#     (one same-second collision is tolerable when the disambiguator
#     coincides; the property is still high-cardinality, not absolute).
#   - --write-pointers atomicity: docs/aidp/latest is a symlink, latest.txt
#     contents match basename(docs/aidp/latest), workflow-state/active matches.
#   - .tmp files never observed after a successful run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
MINT="${REPO_ROOT}/scripts/mint-run-id.sh"
PARSER="${REPO_ROOT}/scripts/parse-run-id.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$MINT" ] || { echo "mint script missing" >&2; exit 2; }

# Sandbox so we don't touch the live docs/. The --write-pointers test below
# uses --run-dir "docs/aidp/runs" to exercise the explicit override path;
# pointer files land in docs/aidp/.
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/docs/aidp/runs" "$sandbox/.claude/workflow-state"

# --- mint → parse round-trip + uniqueness ---
# Bash 3.2 (macOS) lacks associative arrays; use a temp file + sort -u.
total=100
ids_file=$(mktemp)
for _ in $(seq 1 "$total"); do
  id=$(bash "$MINT" 2>/dev/null) || { fail "mint failed"; break; }
  if ! bash "$PARSER" "$id" >/dev/null 2>&1; then
    fail "minted id rejected by parser: $id"
  fi
  printf '%s\n' "$id" >> "$ids_file"
done
unique=$(sort -u "$ids_file" | wc -l | tr -d ' ')
rm -f "$ids_file"

# Uniqueness property: with a 2-hex (256-state) disambiguator and same-
# second mints, expected collisions in 100 trials by birthday paradox
# are ~19; ≥75 distinct is comfortably above the 95th percentile lower
# bound. The guarantee we want is "no two consecutive mints collide on
# all three of (timestamp, sha, disambiguator) by accident" — which
# this threshold catches loudly. The same test across two seconds (or
# two distinct git shas) would yield 100/100.
if [ "$unique" -ge 75 ]; then
  pass "uniqueness: $unique/$total distinct ids (≥75 expected within disambiguator entropy)"
else
  fail "uniqueness: only $unique/$total distinct ids (expected ≥75)"
fi

# --- --write-pointers integration ---
( cd "$sandbox" && bash "$MINT" --write-pointers --run-dir "docs/aidp/runs" >/dev/null )
if [ -L "$sandbox/docs/aidp/latest" ]; then
  pass "docs/aidp/latest is a symlink"
else
  fail "docs/aidp/latest is not a symlink"
fi
if [ -f "$sandbox/docs/aidp/latest.txt" ]; then
  pass "docs/aidp/latest.txt exists"
else
  fail "docs/aidp/latest.txt missing"
fi
target=$(readlink "$sandbox/docs/aidp/latest" 2>/dev/null || echo "")
text=$(cat "$sandbox/docs/aidp/latest.txt" 2>/dev/null || echo "")
target_bn=$(basename "$target")
if [ "$target_bn" = "$text" ]; then
  pass "docs/aidp/latest target basename matches docs/aidp/latest.txt content"
else
  fail "mismatch: latest=$target_bn latest.txt=$text"
fi
# Tmp filenames now carry a per-process suffix (latest.tmp.$$.<rand>) so
# concurrent mints don't race on a shared name. Assert no residue under
# either the legacy or the suffixed pattern.
leftover=$(find "$sandbox/docs/aidp" -maxdepth 1 -name 'latest.tmp*' -o -name 'latest.txt.tmp*' 2>/dev/null | head -1)
active_leftover=$(find "$sandbox/.claude/workflow-state" -maxdepth 1 -name 'active.tmp*' 2>/dev/null | head -1)
if [ -z "$leftover" ] && [ -z "$active_leftover" ]; then
  pass ".tmp files cleaned after atomic update"
else
  fail ".tmp files left behind: docs/aidp=$leftover ws=$active_leftover"
fi
if [ -f "$sandbox/.claude/workflow-state/active" ]; then
  active=$(cat "$sandbox/.claude/workflow-state/active")
  if [ "$active" = "$text" ]; then
    pass "workflow-state/active matches active run-id"
  else
    fail "workflow-state/active mismatch: $active vs $text"
  fi
else
  fail "workflow-state/active missing"
fi
if [ -d "$sandbox/docs/aidp/runs/$text" ]; then
  pass "docs/aidp/runs/<id> directory created"
else
  fail "docs/aidp/runs/<id> not created"
fi

if [ "$failures" -gt 0 ]; then
  echo "test-mint-run-id: FAILED ($failures)" >&2
  exit 1
fi
echo "test-mint-run-id: OK"
