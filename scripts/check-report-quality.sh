#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/lib/project-root.sh
source "${SCRIPT_DIR}/lib/project-root.sh"
AIDP_PROJECT_ROOT="${AIDP_PROJECT_ROOT:-$(aidp_resolve_project_root)}" || {
  echo "check-report-quality: ERROR: could not resolve AIDP_PROJECT_ROOT" >&2; exit 2; }
AIDP_ARTIFACTS_ROOT="${AIDP_ARTIFACTS_ROOT:-$(aidp_resolve_artifacts_root "$AIDP_PROJECT_ROOT")}" || {
  echo "check-report-quality: ERROR: could not resolve AIDP_ARTIFACTS_ROOT" >&2; exit 2; }
# shellcheck source=scripts/harness-lib.sh
source "${SCRIPT_DIR}/harness-lib.sh"
harness_cd_repo_root

errors=0
strict_mode="${REPORT_QUALITY_REQUIRE_CONTENT:-0}"

# Boundary parsing: typed flags from untrusted env vars. Fail closed on any
# value outside the allowlist. See .claude/rules/boundary-parse-dont-validate.md.
#
# REPORT_QUALITY_PHASE — when the smoke gate runs:
#   post-release (default): the run already took its release decision; the
#     verify-report's "Release approved" line MUST be approved/rejected.
#   pre-release: the lean /ship path runs smoke BEFORE release; "pending"
#     is the legitimate placeholder. Accept it.
#
# REPORT_TEST_OPTIONAL — whether test-report.md is required:
#   0 (default): historical strict behavior; missing file fails in strict mode.
#   1: lean /ship paths that skip the tester phase legitimately omit it; a
#      missing file is a skip, never a fail.
phase_raw="${REPORT_QUALITY_PHASE:-post-release}"
case "$phase_raw" in
  pre-release|post-release) phase="$phase_raw" ;;
  *)
    echo "report-quality: ERROR: invalid REPORT_QUALITY_PHASE '$phase_raw' (expected pre-release|post-release)" >&2
    exit 2
    ;;
esac
test_optional_raw="${REPORT_TEST_OPTIONAL:-0}"
case "$test_optional_raw" in
  0|1) test_optional="$test_optional_raw" ;;
  *)
    echo "report-quality: ERROR: invalid REPORT_TEST_OPTIONAL '$test_optional_raw' (expected 0|1)" >&2
    exit 2
    ;;
esac

fail() {
  echo "report-quality: ERROR: $*"
  errors=$((errors + 1))
}

note() {
  echo "report-quality: $*"
}

has_rg() {
  command -v rg >/dev/null 2>&1
}

match_file() {
  local pattern="$1"
  local file="$2"

  if has_rg; then
    rg -q -- "$pattern" "$file"
  else
    grep -Eq -- "$pattern" "$file"
  fi
}

match_stdin() {
  local pattern="$1"

  if has_rg; then
    rg -q -- "$pattern"
  else
    grep -Eq -- "$pattern"
  fi
}

count_stdin() {
  local pattern="$1"

  if has_rg; then
    rg -c -- "$pattern" || true
  else
    grep -E -c -- "$pattern" || true
  fi
}

require_heading() {
  local file="$1"
  local heading="$2"

  if ! match_file "^${heading}$" "$file"; then
    fail "$file missing heading: ${heading}"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! match_file "$pattern" "$file"; then
    fail "$file missing or empty field: ${label}"
  fi
}

normalize_value() {
  # Trim surrounding whitespace, then strip leading/trailing markdown emphasis
  # wrappers (backticks, asterisks, underscores, single/double quotes), then
  # lowercase. Stripping is symmetric and only touches the outermost characters
  # — interior characters are preserved. Idempotent.
  printf '%s' "$1" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | sed 's/^[`*_"'"'"']*//; s/[`*_"'"'"']*$//' \
    | tr '[:upper:]' '[:lower:]'
}

official_sources_present() {
  # Returns 0 iff the file has an `Official sources:` line with either:
  #   (a) a non-empty inline value on the same line, OR
  #   (b) at least one indented `-` sub-bullet with non-empty text in the
  #       block immediately following (terminated by a blank line or any
  #       non-indented line).
  local file="$1"
  awk '
    BEGIN { found = 0 }
    /^- Official sources:[[:space:]]*$/ {
      # Header with no inline value — scan following indented sub-bullets.
      in_block = 1
      next
    }
    /^- Official sources:[[:space:]]+[^[:space:]]/ {
      found = 1
      exit
    }
    in_block == 1 {
      if ($0 ~ /^[[:space:]]*$/) { in_block = 0; next }
      if ($0 ~ /^[[:space:]]+-[[:space:]]+[^[:space:]]/) { found = 1; exit }
      # Non-indented line ends the block.
      if ($0 !~ /^[[:space:]]/) { in_block = 0 }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

evidence_block_has_local_file() {
  # Returns 0 iff the piped stdin has at least one citation-shaped local-file
  # token: a path with one of the recognized source extensions.
  match_stdin '[A-Za-z0-9_./-]+\.(md|yaml|yml|json|ts|tsx|js|py|go|rs|sh|toml)([^A-Za-z0-9]|$)'
}

is_unset_value() {
  local value
  value="$(normalize_value "$1")"
  [[ "$value" =~ ^$|^tbd$|^todo$|^pending$|^unknown$ ]]
}

validate_approval_value() {
  local file="$1"
  local label="$2"
  local raw_value="$3"
  # Mode: 0 = strict (must be approved/rejected/etc); 1 = bare N/A allowed
  # (legacy, used for elevated-risk slot on low-risk plans); 2 = N/A allowed
  # only with rationale (`N/A — <rationale>`), used for Plan/Release on
  # low-risk plans.
  local na_mode="$4"
  local value

  value="$(normalize_value "$raw_value")"

  # Pre-release smoke runs before the release decision; "pending" is the
  # legitimate placeholder ONLY for the Release-approved slot in that phase.
  # All other slots and phases keep the strict placeholder rejection.
  if [ "$phase" = "pre-release" ] && [ "$label" = "Release approved" ] \
     && [[ "$value" =~ ^pending$ ]]; then
    return
  fi

  if is_unset_value "$value"; then
    fail "$file approval gate '${label}' is missing (use approved/rejected and avoid placeholders)"
    return
  fi

  if [[ "$value" =~ ^approved$|^rejected$|^yes$|^no$|^granted$|^denied$|^true$|^false$ ]]; then
    return
  fi

  if [ "$na_mode" = "1" ] && [[ "$value" =~ ^n/?a$|^na$|^not[[:space:]]+required$ ]]; then
    return
  fi

  # Mode 1 also accepts the rationale form for symmetry.
  # Mode 2 requires the rationale form: `N/A — <rationale>` or `N/A - <rationale>`.
  if [[ "$na_mode" = "1" || "$na_mode" = "2" ]] \
     && [[ "$value" =~ ^n/?a[[:space:]]*[—-][[:space:]]*[^[:space:]] ]]; then
    return
  fi

  fail "$file approval gate '${label}' has invalid value '$raw_value'"
}

check_review_report() {
  local file="$1"

  require_heading "$file" '## Findings \(Highest Severity First\)'
  require_heading "$file" '## Blocking Findings \(Tool-Derived\)'
  require_heading "$file" '## Advisory Findings \(Model\)'
  require_heading "$file" '## Evidence'
  require_heading "$file" '## Residual Risks'
  require_heading "$file" '## Recommendation'

  if ! official_sources_present "$file"; then
    fail "$file missing or empty field: Official sources"
  fi
  require_pattern "$file" '^- Unsourced claims rejected:[[:space:]]+[^[:space:]]' 'Unsourced claims rejected'

  # Risk-tier-aware evidence citation check. If the report carries a
  # `- Risk tier:` line and it normalizes to `low`, accept either an http(s)
  # URL or at least one local-file citation. Otherwise (medium/high or no
  # risk tier present), require an http(s) URL — preserving prior behavior.
  local risk_tier
  risk_tier="$(sed -n 's/^- Risk tier:[[:space:]]*//p' "$file" | head -n1)"
  risk_tier="$(normalize_value "$risk_tier")"

  local evidence_block
  evidence_block="$(awk '/^## Evidence$/{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"

  if [ "$risk_tier" = "low" ]; then
    if ! { printf '%s\n' "$evidence_block" | match_stdin 'https?://'; } \
       && ! { printf '%s\n' "$evidence_block" | evidence_block_has_local_file; }; then
      fail "$file evidence section must include at least one citation URL or local-file citation"
    fi
  else
    if ! printf '%s\n' "$evidence_block" | match_stdin 'https?://'; then
      fail "$file evidence section must include at least one citation URL"
    fi
  fi
}

section_has_content() {
  local file="$1"
  local heading="$2"
  local body

  body="$(awk -v h="$heading" '$0 ~ "^"h"$"{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"
  # Strip blank lines and check for non-whitespace content
  printf '%s\n' "$body" | match_stdin '[^[:space:]]'
}

check_test_report() {
  local file="$1"

  require_heading "$file" '## Summary'
  require_heading "$file" '## Property-Based Tests'
  require_heading "$file" '## Contract Tests'
  require_heading "$file" '## Integration Tests'
  require_heading "$file" '## Blocking Failures'
  require_heading "$file" '## Retry and Triage Notes'

  if ! section_has_content "$file" '## Property-Based Tests'; then
    fail "$file section '## Property-Based Tests' has no content"
  fi
  if ! section_has_content "$file" '## Contract Tests'; then
    fail "$file section '## Contract Tests' has no content"
  fi

  require_pattern "$file" '^- Retry count:[[:space:]]+[^[:space:]]' 'Retry count'
  require_pattern "$file" '^- Flaky tests observed:[[:space:]]+[^[:space:]]' 'Flaky tests observed'
  require_pattern "$file" '^- Root cause notes:[[:space:]]+[^[:space:]]' 'Root cause notes'
}

check_verify_report() {
  local file="$1"

  require_heading "$file" '## Context'
  require_heading "$file" '## Gate Results'
  require_heading "$file" '## Retry Envelope'
  require_heading "$file" '## Decision'
  require_heading "$file" '## Finding Classification'
  require_heading "$file" '## Human Approval Checkpoints'
  require_heading "$file" '## Residual Risk and Follow-ups'

  require_pattern "$file" '^- Retry count:[[:space:]]+[^[:space:]]' 'Retry count'
  require_pattern "$file" '^- Final exit codes per gate:[[:space:]]+[^[:space:]]' 'Final exit codes per gate'

  require_pattern "$file" '^- Risk tier:[[:space:]]+[^[:space:]]' 'Risk tier'
  require_pattern "$file" '^1\. Plan approved:[[:space:]]+[^[:space:]]' 'Plan approved'
  # shellcheck disable=SC2016 # backticks are literal markdown in the regex pattern, not command substitution
  require_pattern "$file" '^2\. Elevated-risk implementation approved \(required for `medium` and `high` risk\):[[:space:]]+[^[:space:]]' 'Elevated-risk implementation approved'
  require_pattern "$file" '^3\. Release approved:[[:space:]]+[^[:space:]]' 'Release approved'

  local approval_block
  approval_block="$(awk '/^## Human Approval Checkpoints$/{flag=1;next} /^## /&&flag{exit} flag{print}' "$file")"

  local approver_count
  local date_count
  local link_count
  approver_count="$(printf '%s\n' "$approval_block" | count_stdin 'Approver:[[:space:]]+[^[:space:]]')"
  date_count="$(printf '%s\n' "$approval_block" | count_stdin 'Date:[[:space:]]+[^[:space:]]')"
  link_count="$(printf '%s\n' "$approval_block" | count_stdin 'Evidence link:[[:space:]]+[^[:space:]]')"

  if [ "$approver_count" -lt 3 ]; then
    fail "$file human approval checkpoints require approver metadata (3 entries)"
  fi
  if [ "$date_count" -lt 3 ]; then
    fail "$file human approval checkpoints require date metadata (3 entries)"
  fi
  if [ "$link_count" -lt 3 ]; then
    fail "$file human approval checkpoints require evidence links (3 entries)"
  fi

  local risk_tier
  local plan_approval
  local elevated_risk_approval
  local release_approval

  risk_tier="$(sed -n 's/^- Risk tier:[[:space:]]*//p' "$file" | head -n1)"
  risk_tier="$(normalize_value "$risk_tier")"
  plan_approval="$(sed -n 's/^1\. Plan approved:[[:space:]]*//p' "$file" | head -n1)"
  # shellcheck disable=SC2016 # backticks are literal markdown inside the sed pattern, not command substitution
  elevated_risk_approval="$(sed -n 's/^2\. Elevated-risk implementation approved (required for `medium` and `high` risk):[[:space:]]*//p' "$file" | head -n1)"
  release_approval="$(sed -n 's/^3\. Release approved:[[:space:]]*//p' "$file" | head -n1)"

  if ! [[ "$risk_tier" =~ ^low$|^medium$|^high$ ]]; then
    fail "$file risk tier must be one of low|medium|high"
    return
  fi

  if [ "$risk_tier" = "low" ]; then
    # Plan & Release: N/A allowed only with rationale.
    validate_approval_value "$file" "Plan approved" "$plan_approval" 2
    validate_approval_value "$file" "Release approved" "$release_approval" 2
    # Elevated-risk: bare N/A allowed (legacy convenience for low-risk runs).
    validate_approval_value "$file" "Elevated-risk implementation approved" "$elevated_risk_approval" 1
  else
    validate_approval_value "$file" "Plan approved" "$plan_approval" 0
    validate_approval_value "$file" "Release approved" "$release_approval" 0
    validate_approval_value "$file" "Elevated-risk implementation approved" "$elevated_risk_approval" 0
  fi
}

check_one() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then
    # Lean /ship paths legitimately skip the tester phase; honor the explicit
    # opt-in even under strict mode for the test-report only.
    if [ "$label" = "test" ] && [ "$test_optional" = "1" ]; then
      note "skipping test-report checks (REPORT_TEST_OPTIONAL=1; lean ship path)"
      return
    fi
    if [ "$strict_mode" = "1" ]; then
      fail "missing report file: $file"
    else
      note "skipping $label checks for missing $file (set REPORT_QUALITY_REQUIRE_CONTENT=1 to enforce)"
    fi
    return
  fi

  if [ ! -s "$file" ]; then
    if [ "$strict_mode" = "1" ]; then
      fail "$file is empty (strict mode)"
    else
      note "skipping $label checks for empty $file (set REPORT_QUALITY_REQUIRE_CONTENT=1 to enforce)"
    fi
    return
  fi

  case "$label" in
    review) check_review_report "$file" ;;
    test) check_test_report "$file" ;;
    verify) check_verify_report "$file" ;;
    *) fail "unknown report label: $label" ;;
  esac
}

# Per-run report paths.
#   1. Honor explicit env overrides (REPORT_*_PATH) when set — these
#      win unconditionally so callers can target a specific run dir.
#   2. Otherwise, if RUN_DIR is set, default to ${RUN_DIR}/<report>.md.
#   3. Otherwise, anchor to ${AIDP_ARTIFACTS_ROOT}/latest/<report>.md so
#      this script remains usable in repos that haven't minted a run yet.
#      The cwd-relative `docs/aidp/latest` / `docs/<report>.md` fallbacks are
#      gone — they would resolve under the plugin after harness_cd_repo_root.
default_report_path() {
  local name="$1"
  if [ -n "${RUN_DIR:-}" ]; then
    printf '%s/%s\n' "$RUN_DIR" "$name"
  elif [ -L "${AIDP_ARTIFACTS_ROOT}/latest" ] || [ -d "${AIDP_ARTIFACTS_ROOT}/latest" ]; then
    printf '%s/latest/%s\n' "$AIDP_ARTIFACTS_ROOT" "$name"
  else
    # Top-level fallback for repos that haven't minted a run yet. Still
    # absolute (anchored to AIDP_ARTIFACTS_ROOT) — never cwd-relative.
    printf '%s/%s\n' "$AIDP_ARTIFACTS_ROOT" "$name"
  fi
}

review_path="${REPORT_REVIEW_PATH:-$(default_report_path review-report.md)}"
test_path="${REPORT_TEST_PATH:-$(default_report_path test-report.md)}"
verify_path="${REPORT_VERIFY_PATH:-$(default_report_path verify-report.md)}"

# Manifest-aware required set.
#
# When a run manifest exists, treat the set of artifact paths it lists as the
# authoritative "produced this run" set. A report is only enforced if its
# expected path appears in that list. Reports NOT in the manifest are skipped
# silently — lean /ship pipelines that don't run the tester phase legitimately
# omit test-report.md, and the gate must not punish that.
#
# When the manifest is absent we fall back to the historical behavior: all
# three reports are considered candidates and `check_one` decides per-file
# based on REPORT_QUALITY_REQUIRE_CONTENT.
#
# Manifest discovery order:
#   1. ${RUN_DIR}/manifest.json (when RUN_DIR set)
#   2. ${AIDP_ARTIFACTS_ROOT}/latest/manifest.json (when no RUN_DIR)
# We do NOT extend the manifest schema here — only its consumer surface.
# All ingress goes through the canonical boundary parser.
manifest_path=""
if [ -n "${RUN_DIR:-}" ] && [ -f "${RUN_DIR}/manifest.json" ]; then
  manifest_path="${RUN_DIR}/manifest.json"
elif [ -z "${RUN_DIR:-}" ] && [ -f "${AIDP_ARTIFACTS_ROOT}/latest/manifest.json" ]; then
  manifest_path="${AIDP_ARTIFACTS_ROOT}/latest/manifest.json"
fi

# Manifest artifact paths, one per line (relative to the manifest's run-dir).
# Empty when no manifest exists.
manifest_artifacts=""
if [ -n "$manifest_path" ]; then
  parsed=""
  if parsed=$(bash "${SCRIPT_DIR}/parse-manifest.sh" "$manifest_path" 2>/dev/null); then
    manifest_artifacts=$(printf '%s\n' "$parsed" | sed -n 's/^artifact=//p')
  else
    note "manifest present but parser rejected it; falling back to legacy enforcement: $manifest_path"
    manifest_path=""
  fi
fi

# is_in_manifest <expected_report_path>
#   Returns 0 iff the report's path matches an artifact entry in the manifest.
#   Comparison is by basename + suffix-match against the relative artifact
#   path (so both `RUN_DIR/test-report.md` and a manifest entry `test-report.md`
#   match, and a future nested layout would still match if the trailing path
#   segment equals the report file name).
is_in_manifest() {
  local report_path="$1"
  local base
  base=$(basename -- "$report_path")
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "$(basename -- "$entry")" = "$base" ] && return 0
  done <<< "$manifest_artifacts"
  return 1
}

maybe_check() {
  local path="$1" label="$2"
  if [ -n "$manifest_path" ] && ! is_in_manifest "$path"; then
    note "skipping $label checks: $path not listed in manifest ($manifest_path)"
    return 0
  fi
  check_one "$path" "$label"
}

maybe_check "$review_path" review
maybe_check "$test_path" test
maybe_check "$verify_path" verify

if [ "$errors" -gt 0 ]; then
  echo "report-quality: FAILED with $errors issue(s)"
  exit 1
fi

echo "report-quality: OK"
exit 0
