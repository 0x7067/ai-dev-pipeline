#!/usr/bin/env bash
# Contract test: parse-manifest.sh accepts well-formed v1 manifests.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-manifest.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

tmpdir=$(mktemp -d -t manifest-accept.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

# Case 1: minimal valid manifest with empty artifacts array.
mkdir -p "$tmpdir/run1"
cat > "$tmpdir/run1/manifest.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3-7f","started_at":"2026-05-08T14:30:22Z","ended_at":"2026-05-08T14:30:25Z","command":"ship","mode":"auto","risk_tier":"low","status":"ok","git":{"head":"","branch":"","dirty":false},"artifacts":[]}
EOF

if out=$(bash "$PARSER" "$tmpdir/run1/manifest.json" 2>&1); then
  if grep -q '^schema=run-manifest/v1$' <<<"$out" \
     && grep -q '^run_id=20260508T143022-a1b2c3-7f$' <<<"$out" \
     && grep -q '^artifact_count=0$' <<<"$out"; then
    pass "minimal manifest accepted"
  else
    fail "minimal manifest output unexpected: $out"
  fi
else
  fail "minimal manifest rejected: $out"
fi

# Case 2: manifest with two artifacts, both legal relative paths.
mkdir -p "$tmpdir/run2"
echo "plan body" > "$tmpdir/run2/current-plan.md"
mkdir -p "$tmpdir/run2/research"
echo "rb" > "$tmpdir/run2/research/topic.md"
cat > "$tmpdir/run2/manifest.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","started_at":"","ended_at":"","command":"ship","mode":"","risk_tier":"","status":"ok","git":{"head":"","branch":"","dirty":false},"artifacts":[
  {"kind":"plan","path":"current-plan.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000","bytes":10},
  {"kind":"research","path":"research/topic.md","sha256":"1111111111111111111111111111111111111111111111111111111111111111","bytes":3}
]}
EOF

if out=$(bash "$PARSER" "$tmpdir/run2/manifest.json" 2>&1); then
  if grep -q '^artifact_count=2$' <<<"$out" \
     && grep -q '^artifact=current-plan.md$' <<<"$out" \
     && grep -q '^artifact=research/topic.md$' <<<"$out"; then
    pass "two-artifact manifest accepted"
  else
    fail "two-artifact summary unexpected: $out"
  fi
else
  fail "two-artifact manifest rejected: $out"
fi

# Case 3: pretty-printed JSON with whitespace.
mkdir -p "$tmpdir/run3"
cat > "$tmpdir/run3/manifest.json" <<'EOF'
{
  "schema" : "run-manifest/v1",
  "run_id" : "20260508T143022Z-a1b2c3-00",
  "command": "ship",
  "status" : "ok",
  "artifacts": []
}
EOF

if out=$(bash "$PARSER" "$tmpdir/run3/manifest.json" 2>&1); then
  pass "pretty-printed manifest accepted"
else
  fail "pretty-printed manifest rejected: $out"
fi

if [ "$failures" -gt 0 ]; then
  echo "parse_accept_test: FAILED ($failures)" >&2
  exit 1
fi
echo "parse_accept_test: OK"
