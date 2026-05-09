#!/usr/bin/env bash
# Contract test: parse-manifest.sh rejects malformed v1 manifests.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
PARSER="${REPO_ROOT}/scripts/parse-manifest.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

[ -f "$PARSER" ] || { echo "parser missing at $PARSER" >&2; exit 2; }

tmpdir=$(mktemp -d -t manifest-reject.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

expect_reject() {
  local label="$1" file="$2"
  if bash "$PARSER" "$file" >/dev/null 2>&1; then
    fail "$label: parser accepted bad manifest"
  else
    local rc=$?
    if [ "$rc" -ne 2 ]; then
      fail "$label: rejected with rc=$rc, want 2"
    else
      pass "$label"
    fi
  fi
}

# 1. Missing schema key.
mkdir -p "$tmpdir/c1"
cat > "$tmpdir/c1/m.json" <<'EOF'
{"run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[]}
EOF
expect_reject "missing schema" "$tmpdir/c1/m.json"

# 2. Wrong schema value.
mkdir -p "$tmpdir/c2"
cat > "$tmpdir/c2/m.json" <<'EOF'
{"schema":"run-manifest/v2","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[]}
EOF
expect_reject "wrong schema value" "$tmpdir/c2/m.json"

# 3. Missing run_id.
mkdir -p "$tmpdir/c3"
cat > "$tmpdir/c3/m.json" <<'EOF'
{"schema":"run-manifest/v1","command":"ship","status":"ok","artifacts":[]}
EOF
expect_reject "missing run_id" "$tmpdir/c3/m.json"

# 4. Missing command.
mkdir -p "$tmpdir/c4"
cat > "$tmpdir/c4/m.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","status":"ok","artifacts":[]}
EOF
expect_reject "missing command" "$tmpdir/c4/m.json"

# 5. Missing status.
mkdir -p "$tmpdir/c5"
cat > "$tmpdir/c5/m.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","artifacts":[]}
EOF
expect_reject "missing status" "$tmpdir/c5/m.json"

# 6. Missing artifacts.
mkdir -p "$tmpdir/c6"
cat > "$tmpdir/c6/m.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok"}
EOF
expect_reject "missing artifacts" "$tmpdir/c6/m.json"

# 7. Bad run_id (regex mismatch).
mkdir -p "$tmpdir/c7"
cat > "$tmpdir/c7/m.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"NOT-A-RUN-ID","command":"ship","status":"ok","artifacts":[]}
EOF
expect_reject "bad run_id" "$tmpdir/c7/m.json"

# 8. Artifact entry missing required key (sha256).
mkdir -p "$tmpdir/c8"
cat > "$tmpdir/c8/m.json" <<'EOF'
{"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[{"kind":"plan","path":"current-plan.md","bytes":10}]}
EOF
expect_reject "artifact missing sha256" "$tmpdir/c8/m.json"

# 9. REGRESSION (review BLOCKING-1): top-level keys missing but nested
# copies present inside artifacts[]. The depth-blind extractor previously
# accepted this; the depth-aware version must reject.
mkdir -p "$tmpdir/c9"
cat > "$tmpdir/c9/m.json" <<'EOF'
{"artifacts":[{"kind":"other","path":"x","sha256":"0000000000000000000000000000000000000000000000000000000000000000","bytes":1,"schema":"run-manifest/v1","run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok"}]}
EOF
expect_reject "smuggled top-level keys (nested only)" "$tmpdir/c9/m.json"

# 9b. Schema present nested but absent at top level (artifacts has its own schema).
mkdir -p "$tmpdir/c9b"
cat > "$tmpdir/c9b/m.json" <<'EOF'
{"run_id":"20260508T143022-a1b2c3","command":"ship","status":"ok","artifacts":[{"kind":"other","path":"x","sha256":"0000000000000000000000000000000000000000000000000000000000000000","bytes":1,"schema":"run-manifest/v1"}]}
EOF
expect_reject "schema only nested, missing at top" "$tmpdir/c9b/m.json"

if [ "$failures" -gt 0 ]; then
  echo "parse_reject_test: FAILED ($failures)" >&2
  exit 1
fi
echo "parse_reject_test: OK"
