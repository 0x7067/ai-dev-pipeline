#!/usr/bin/env bash
# Contract tests for the harness-lib resolver helpers introduced in v0.4.0:
#   harness_parse_plugin_root
#   harness_resolve_artifact
#   harness_classify_install_mode
#
# Invariants exercised:
#   - Boundary parser rejects unset, empty, non-dir, dir-without-manifest.
#   - Resolver: repo-local precedence (vendored wins).
#   - Resolver: plugin-root fallback when repo copy is absent.
#   - Resolver: structured NotFound when neither side has the artifact.
#   - Idempotence: same inputs -> same answer.
#   - Mode classifier: Vendored / ZeroSetup / Broken.
#   - Path with spaces in CLAUDE_PLUGIN_ROOT round-trips.
#
# This test creates throwaway plugin-root and consuming-repo directories under
# mktemp so it never mutates the real repo.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." >/dev/null 2>&1 && pwd -P)"
LIB="${REPO_ROOT}/scripts/harness-lib.sh"

# shellcheck source=scripts/harness-lib.sh disable=SC1091
source "${LIB}"

failures=0
pass() { echo "  ok: $1"; }
fail() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

# Track every tmp dir we create so cleanup runs even if a case fails mid-way
# or the test is interrupted. Per-case rm -rf at the end of each function is
# best-effort; this trap is the guarantee.
TMP_DIRS=()
register_tmp() { TMP_DIRS+=("$1"); }
cleanup_tmp_dirs() {
  local d
  for d in "${TMP_DIRS[@]:-}"; do
    [ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"
  done
}
trap cleanup_tmp_dirs EXIT INT TERM

# Build a fake plugin install: a directory with .claude-plugin/plugin.json plus
# a known artifact. Returns the absolute path on stdout.
# canonicalize: resolve symlinks (mktemp on macOS returns /var/folders/...
# but the kernel reports /private/var/folders/... after pwd -P). Tests must
# compare against the canonicalized form, same as the resolver does.
canonicalize() {
  ( cd "$1" >/dev/null 2>&1 && pwd -P )
}

make_fake_plugin_root() {
  local label="${1:-plugin}"
  local root
  root="$(mktemp -d -t "resolver-${label}-XXXXXX")"
  register_tmp "${root}"
  root="$(canonicalize "${root}")"
  register_tmp "${root}"
  mkdir -p "${root}/.claude-plugin" "${root}/docs/templates" "${root}/scripts"
  printf '{"name":"fake","version":"0.0.0"}\n' > "${root}/.claude-plugin/plugin.json"
  printf '# plugin template\n' > "${root}/docs/templates/test-template.md"
  printf '#!/usr/bin/env bash\necho ok\n' > "${root}/scripts/run-verification-gates.sh"
  chmod +x "${root}/scripts/run-verification-gates.sh"
  printf '%s\n' "${root}"
}

# ----------------------------------------------------------------------------
# 1. harness_parse_plugin_root: accept/reject contract
# ----------------------------------------------------------------------------

case_parse_plugin_root() {
  local plugin_root
  plugin_root="$(make_fake_plugin_root parse)"

  # Accept: explicit valid path.
  local got
  got="$(harness_parse_plugin_root "${plugin_root}" 2>/dev/null)" || got=""
  if [ "${got}" = "${plugin_root}" ]; then
    pass "parse_plugin_root accepts valid path"
  else
    fail "parse_plugin_root rejected valid path: got=${got} expected=${plugin_root}"
  fi

  # Reject: empty.
  if ! harness_parse_plugin_root "" >/dev/null 2>&1; then
    pass "parse_plugin_root rejects empty"
  else
    fail "parse_plugin_root accepted empty input"
  fi

  # Reject: non-existent dir.
  if ! harness_parse_plugin_root "/nonexistent/path/${RANDOM}" >/dev/null 2>&1; then
    pass "parse_plugin_root rejects missing directory"
  else
    fail "parse_plugin_root accepted missing directory"
  fi

  # Reject: directory missing manifest.
  local empty_dir
  empty_dir="$(mktemp -d -t resolver-empty-XXXXXX)"
  register_tmp "${empty_dir}"
  if ! harness_parse_plugin_root "${empty_dir}" >/dev/null 2>&1; then
    pass "parse_plugin_root rejects dir without plugin.json"
  else
    fail "parse_plugin_root accepted dir without manifest"
  fi

  # Reject: unset env (no arg).
  ( unset CLAUDE_PLUGIN_ROOT
    if ! harness_parse_plugin_root >/dev/null 2>&1; then exit 0; else exit 1; fi
  ) && pass "parse_plugin_root rejects unset env" || fail "parse_plugin_root accepted unset env"

  rm -rf "${plugin_root}" "${empty_dir}"
}

# ----------------------------------------------------------------------------
# 2. harness_resolve_artifact: precedence, fallback, NotFound
# ----------------------------------------------------------------------------

case_resolve_repo_precedence() {
  local plugin_root repo_root
  plugin_root="$(make_fake_plugin_root precedence-plugin)"
  repo_root="$(mktemp -d -t resolver-repo-XXXXXX)"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"
  mkdir -p "${repo_root}/docs/templates"
  printf '# REPO\n' > "${repo_root}/docs/templates/test-template.md"

  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    got="$(harness_resolve_artifact docs/templates/test-template.md 2>/dev/null)"
    [ "${got}" = "${repo_root}/docs/templates/test-template.md" ]
  ) && pass "resolve_artifact: repo copy wins over plugin copy" \
    || fail "resolve_artifact: repo precedence violated"

  rm -rf "${plugin_root}" "${repo_root}"
}

case_resolve_plugin_fallback() {
  local plugin_root repo_root
  plugin_root="$(make_fake_plugin_root fallback-plugin)"
  repo_root="$(mktemp -d -t resolver-repo-XXXXXX)"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"
  # repo has no docs/templates/test-template.md

  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    got="$(harness_resolve_artifact docs/templates/test-template.md 2>/dev/null)"
    [ "${got}" = "${plugin_root}/docs/templates/test-template.md" ]
  ) && pass "resolve_artifact: falls back to plugin root when repo missing" \
    || fail "resolve_artifact: plugin-root fallback failed"

  rm -rf "${plugin_root}" "${repo_root}"
}

case_resolve_not_found() {
  local plugin_root repo_root
  plugin_root="$(make_fake_plugin_root notfound-plugin)"
  repo_root="$(mktemp -d -t resolver-repo-XXXXXX)"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"

  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    err="$(harness_resolve_artifact docs/templates/missing.md 2>&1 1>/dev/null)"
    rc=$?
    [ "${rc}" -ne 0 ] || exit 1
    case "${err}" in
      *NotFound*searched=*) exit 0 ;;
      *) exit 1 ;;
    esac
  ) && pass "resolve_artifact: structured NotFound when neither side has artifact" \
    || fail "resolve_artifact: NotFound error not structured as expected"

  rm -rf "${plugin_root}" "${repo_root}"
}

case_resolve_idempotent() {
  local plugin_root repo_root
  plugin_root="$(make_fake_plugin_root idem-plugin)"
  repo_root="$(mktemp -d -t resolver-repo-XXXXXX)"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"

  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    a="$(harness_resolve_artifact docs/templates/test-template.md 2>/dev/null)"
    b="$(harness_resolve_artifact docs/templates/test-template.md 2>/dev/null)"
    [ "${a}" = "${b}" ] && [ -n "${a}" ]
  ) && pass "resolve_artifact: idempotent on repeat call" \
    || fail "resolve_artifact: not idempotent"

  rm -rf "${plugin_root}" "${repo_root}"
}

case_resolve_rejects_absolute() {
  if ! harness_resolve_artifact /etc/passwd >/dev/null 2>&1; then
    pass "resolve_artifact: rejects absolute path argument"
  else
    fail "resolve_artifact: accepted absolute path argument"
  fi
}

# Boundary parse-don't-validate: a relative path containing ".." segments is
# untrusted input that could escape both the repo root and the plugin root.
# The resolver MUST reject before any filesystem probe.
case_resolve_rejects_traversal() {
  local err rc
  err="$(harness_resolve_artifact ../../etc/passwd 2>&1 1>/dev/null)"; rc=$?
  if [ "${rc}" -eq 2 ] && [[ "${err}" == *"path traversal"* || "${err}" == *"\"..\""* ]]; then
    pass "resolve_artifact: rejects leading ../.. traversal with exit 2"
  else
    fail "resolve_artifact: did not reject leading ../.. (rc=${rc} err=${err})"
  fi

  err="$(harness_resolve_artifact docs/../../../etc/passwd 2>&1 1>/dev/null)"; rc=$?
  if [ "${rc}" -eq 2 ]; then
    pass "resolve_artifact: rejects embedded /../ traversal"
  else
    fail "resolve_artifact: did not reject embedded /../ (rc=${rc})"
  fi

  err="$(harness_resolve_artifact .. 2>&1 1>/dev/null)"; rc=$?
  if [ "${rc}" -eq 2 ]; then
    pass "resolve_artifact: rejects bare .. argument"
  else
    fail "resolve_artifact: did not reject bare .. (rc=${rc})"
  fi
}

case_resolve_path_with_spaces() {
  # CLAUDE_PLUGIN_ROOT containing a space must round-trip cleanly.
  local parent root
  parent="$(mktemp -d -t "resolver space XXXXXX")"
  register_tmp "${parent}"
  parent="$(canonicalize "${parent}")"
  root="${parent}/plugin with space"
  mkdir -p "${root}/.claude-plugin" "${root}/docs/templates"
  printf '{}\n' > "${root}/.claude-plugin/plugin.json"
  printf 'x\n' > "${root}/docs/templates/test-template.md"

  local repo_root
  repo_root="$(mktemp -d -t "resolver repo XXXXXX")"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"

  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${root}"
    got="$(harness_resolve_artifact docs/templates/test-template.md 2>/dev/null)"
    [ "${got}" = "${root}/docs/templates/test-template.md" ]
  ) && pass "resolve_artifact: handles paths with spaces" \
    || fail "resolve_artifact: failed on path with spaces"

  rm -rf "${parent}" "${repo_root}"
}

# ----------------------------------------------------------------------------
# 3. harness_classify_install_mode
# ----------------------------------------------------------------------------

case_classify_modes() {
  local plugin_root repo_root
  plugin_root="$(make_fake_plugin_root classify-plugin)"

  # ZeroSetup: repo has no scripts/, plugin root has the gate runner.
  repo_root="$(mktemp -d -t resolver-repo-XXXXXX)"
  register_tmp "${repo_root}"
  repo_root="$(canonicalize "${repo_root}")"
  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    [ "$(harness_classify_install_mode)" = "ZeroSetup" ]
  ) && pass "classify: ZeroSetup when only plugin has gate runner" \
    || fail "classify: ZeroSetup case failed"

  # Vendored: repo has its own scripts/run-verification-gates.sh.
  mkdir -p "${repo_root}/scripts"
  printf '#!/usr/bin/env bash\n' > "${repo_root}/scripts/run-verification-gates.sh"
  ( cd "${repo_root}" || exit 1
    export CLAUDE_PLUGIN_ROOT="${plugin_root}"
    [ "$(harness_classify_install_mode)" = "Vendored" ]
  ) && pass "classify: Vendored when repo has gate runner" \
    || fail "classify: Vendored case failed"

  # Broken: neither side has it.
  local broken_repo
  broken_repo="$(mktemp -d -t resolver-broken-XXXXXX)"
  register_tmp "${broken_repo}"
  ( cd "${broken_repo}" || exit 1
    unset CLAUDE_PLUGIN_ROOT
    out="$(harness_classify_install_mode 2>/dev/null || true)"
    [ "${out}" = "Broken" ]
  ) && pass "classify: Broken when neither side has gate runner" \
    || fail "classify: Broken case failed"

  rm -rf "${plugin_root}" "${repo_root}" "${broken_repo}"
}

# ----------------------------------------------------------------------------
# Run all cases
# ----------------------------------------------------------------------------

echo "test-resolver: starting"
case_parse_plugin_root
case_resolve_repo_precedence
case_resolve_plugin_fallback
case_resolve_not_found
case_resolve_idempotent
case_resolve_rejects_absolute
case_resolve_rejects_traversal
case_resolve_path_with_spaces
case_classify_modes

if [ "${failures}" -eq 0 ]; then
  echo "test-resolver: all cases passed"
  exit 0
fi

echo "test-resolver: ${failures} failure(s)" >&2
exit 1
