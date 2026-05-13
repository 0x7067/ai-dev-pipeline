#!/usr/bin/env bash
# Contract tests for lightweight ADR artifact validation.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/check-adrs.sh"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

make_workdir() { mktemp -d -t adrs-test-XXXXXX; }

run_in_workdir() {
  local work="$1"
  shift
  (
    cd "$work" \
      && mkdir -p scripts/lib .claude-plugin \
      && ln -s "${REPO_ROOT}/scripts/harness-lib.sh" scripts/harness-lib.sh \
      && ln -s "${REPO_ROOT}/scripts/lib/project-root.sh" scripts/lib/project-root.sh \
      && ln -s "$SCRIPT" scripts/check-adrs.sh \
      && printf '{"name":"ai-dev-pipeline","version":"0.0.0"}\n' > .claude-plugin/plugin.json \
      && "$@" bash scripts/check-adrs.sh >/tmp/adrs-test.out 2>&1
  )
}

write_valid_adr() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
# ADR: Keep decisions with run artifacts

Status: accepted
Date: 2026-05-10
Run: 20260510T120000-a1b2c3

## Context

The ship flow needs a durable why without a second decision registry.

## Decision

Store concise ADRs under the active run directory.

## Consequences

Run manifests and summaries can discover the decision record with other artifacts.
EOF
}

work="$(make_workdir)"
if run_in_workdir "$work" env; then
  pass "no ADRs is OK"
else
  fail "empty repo should accept absence of ADRs"
  sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  write_valid_adr docs/aidp/runs/20260510T120000-a1b2c3/adrs/20260510-run-artifact-adrs.md
)
if run_in_workdir "$work" env RUN_DIR=docs/aidp/runs/20260510T120000-a1b2c3; then
  pass "valid ADR under RUN_DIR accepted"
else
  fail "valid ADR under RUN_DIR rejected"
  sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/runs/20260510T120000-a1b2c3/adrs
  cat > docs/aidp/runs/20260510T120000-a1b2c3/adrs/bad.md <<'EOF'
# ADR: Bad

Status: accepted
Date: 2026-05-10
Run: 20260510T120000-a1b2c3

## Context
## Decision
## Consequences
EOF
)
if run_in_workdir "$work" env RUN_DIR=docs/aidp/runs/20260510T120000-a1b2c3; then
  fail "invalid filename should fail"
  sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
else
  if grep -q 'filename must be YYYYMMDD-short-slug.md' /tmp/adrs-test.out; then
    pass "invalid filename rejected"
  else
    fail "invalid filename failure missing"
    sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
  fi
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/runs/20260510T120000-a1b2c3/adrs
  cat > docs/aidp/runs/20260510T120000-a1b2c3/adrs/20260510-empty-context.md <<'EOF'
# ADR: Missing why

Status: accepted
Date: 2026-05-10
Run: 20260510T120000-a1b2c3

## Context

## Decision

Store ADRs in the run directory.

## Consequences

Run summaries can show them.
EOF
)
if run_in_workdir "$work" env RUN_DIR=docs/aidp/runs/20260510T120000-a1b2c3; then
  fail "empty context should fail"
  sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
else
  if grep -q 'no body under ## Context' /tmp/adrs-test.out; then
    pass "empty section body rejected"
  else
    fail "empty section failure missing"
    sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
  fi
fi
rm -rf "$work"

work="$(make_workdir)"
(
  cd "$work" || exit 1
  mkdir -p docs/aidp/runs/20260510T120000-a1b2c3/adrs
  cat > docs/aidp/runs/20260510T120000-a1b2c3/adrs/20260510-placeholder.md <<'EOF'
# ADR: <short decision title>

Status: proposed
Date: 2026-05-10
Run: 20260510T120000-a1b2c3

## Context
## Decision
## Consequences
EOF
)
if run_in_workdir "$work" env RUN_DIR=docs/aidp/runs/20260510T120000-a1b2c3; then
  fail "placeholder ADR should fail"
  sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
else
  if grep -q 'template placeholder' /tmp/adrs-test.out; then
    pass "placeholder text rejected"
  else
    fail "placeholder failure missing"
    sed -e 's/^/    | /' /tmp/adrs-test.out >&2 || true
  fi
fi
rm -rf "$work"

if [ "$failures" -gt 0 ]; then
  echo "test-adrs: FAILED ($failures)" >&2
  exit 1
fi

echo "test-adrs: OK"
