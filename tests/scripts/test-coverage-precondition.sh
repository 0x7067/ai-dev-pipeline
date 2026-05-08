#!/usr/bin/env bash
# Integration tests for scripts/coverage-precondition.sh using mock CLIs on PATH.
#
# Cases:
#   (a) tool present + threshold met            → exit 0, fragment logged
#   (b) tool present + below threshold          → exit 1
#   (c) no tool + no rationale                  → exit 1
#   (d) no tool + rationale via env             → exit 0, rationale in fragment
#   (e) Go-only path with mock `go` printing    → exit 0 when 92.3% >= 80
#       `coverage: 92.3%`

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
SCRIPT="${REPO_ROOT}/scripts/coverage-precondition.sh"

[ -x "$SCRIPT" ] || { echo "missing or non-exec: $SCRIPT" >&2; exit 2; }

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Per-case sandbox: each case runs in its own tmp dir with a curated PATH.
make_sandbox() {
  local d
  d="$(mktemp -d)"
  echo "$d"
}

# shellcheck disable=SC2329 # invoked via `trap cleanup EXIT`
cleanup() {
  [ -n "${SBX:-}" ] && [ -d "$SBX" ] && rm -rf "$SBX"
}
trap cleanup EXIT

# Helper to write an executable mock in $1/bin with name $2 and body $3.
write_mock() {
  local sbx="$1" name="$2" body="$3"
  mkdir -p "$sbx/bin"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$sbx/bin/$name"
  chmod +x "$sbx/bin/$name"
}

run_case() {
  local sbx="$1"
  shift
  # Ensure /usr/bin and /bin are still on PATH so awk/grep/sed work.
  PATH="$sbx/bin:/usr/bin:/bin" \
    COVERAGE_FRAGMENT_OUT="$sbx/precond.md" \
    bash "$SCRIPT" "$@"
}

# ---- (a) pytest present, succeeds → pass ----
SBX="$(make_sandbox)"
(
  cd "$SBX" || exit 1
  : > pyproject.toml
  write_mock "$SBX" pytest 'exit 0'
  if run_case "$SBX" "src/foo.py" >/tmp/out.$$ 2>&1; then
    if grep -q "PASS via pytest" /tmp/out.$$; then
      pass "(a) pytest pass"
    else
      fail "(a) pytest pass — wrong message: $(cat /tmp/out.$$)"
    fi
  else
    fail "(a) pytest pass — exit non-zero: $(cat /tmp/out.$$)"
  fi
  rm -f /tmp/out.$$
)
rm -rf "$SBX"; SBX=""

# ---- (b) pytest present, below threshold → block ----
SBX="$(make_sandbox)"
(
  cd "$SBX" || exit 1
  : > pyproject.toml
  write_mock "$SBX" pytest 'exit 1'
  if run_case "$SBX" "src/foo.py" >/tmp/out.$$ 2>&1; then
    fail "(b) pytest block — should have exited non-zero: $(cat /tmp/out.$$)"
  else
    if grep -q "BLOCKED via pytest" /tmp/out.$$; then
      pass "(b) pytest block"
    else
      fail "(b) pytest block — wrong message: $(cat /tmp/out.$$)"
    fi
  fi
  rm -f /tmp/out.$$
)
rm -rf "$SBX"; SBX=""

# ---- (c) no tool + no rationale → block ----
SBX="$(make_sandbox)"
(
  cd "$SBX" || exit 1
  # No project files, no tools on PATH (only /usr/bin and /bin).
  if COVERAGE_RATIONALE="" run_case "$SBX" "src/foo" </dev/null >/tmp/out.$$ 2>&1; then
    fail "(c) no-tool no-rationale — should block: $(cat /tmp/out.$$)"
  else
    if grep -q "BLOCKED" /tmp/out.$$; then
      pass "(c) no-tool no-rationale blocks"
    else
      fail "(c) no-tool no-rationale — wrong message: $(cat /tmp/out.$$)"
    fi
  fi
  rm -f /tmp/out.$$
)
rm -rf "$SBX"; SBX=""

# ---- (d) no tool + rationale via env → pass + log ----
SBX="$(make_sandbox)"
(
  cd "$SBX" || exit 1
  if COVERAGE_RATIONALE="greenfield project; tests will follow PR-2" \
       run_case "$SBX" "src/foo" >/tmp/out.$$ 2>&1; then
    if grep -q "PASS via rationale-fallback" /tmp/out.$$ \
         && grep -q "rationale: greenfield" "$SBX/precond.md"; then
      pass "(d) no-tool rationale passes + logs"
    else
      fail "(d) no-tool rationale — log content wrong: $(cat "$SBX/precond.md" 2>/dev/null)"
    fi
  else
    fail "(d) no-tool rationale — should have passed: $(cat /tmp/out.$$)"
  fi
  rm -f /tmp/out.$$
)
rm -rf "$SBX"; SBX=""

# ---- (e) Go path: mock go prints `coverage: 92.3%` → pass ----
SBX="$(make_sandbox)"
(
  cd "$SBX" || exit 1
  : > go.mod
  # Mock `go` only prints the line on `go test -cover ...`. The script's
  # detection requires both `go.mod` AND `command -v go`, so the mock
  # satisfies both.
  # shellcheck disable=SC2016 # mock body is bash source for a child shell; $1 must stay literal
  write_mock "$SBX" go '
if [ "$1" = "test" ]; then
  echo "ok  example.com/pkg  0.012s  coverage: 92.3% of statements"
  exit 0
fi
exit 0
'
  if run_case "$SBX" "pkg" >/tmp/out.$$ 2>&1; then
    if grep -q "PASS via gotest" /tmp/out.$$; then
      pass "(e) gotest 92.3% pass"
    else
      fail "(e) gotest 92.3% — wrong message: $(cat /tmp/out.$$)"
    fi
  else
    fail "(e) gotest 92.3% — should have passed: $(cat /tmp/out.$$)"
  fi
  rm -f /tmp/out.$$
)
rm -rf "$SBX"; SBX=""

if [ "$failures" -eq 0 ]; then
  echo "coverage-precondition: ok (5/5)"
  exit 0
fi
echo "coverage-precondition: $failures failure(s)" >&2
exit 1
