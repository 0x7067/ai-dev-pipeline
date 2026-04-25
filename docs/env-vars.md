# Environment Variables

All scripts respect these environment variables for project-specific customization.

## Hooks

| Variable | Default | Description |
|---|---|---|
| `HOOKS_FAST` | `0` | Set to `1` to run hooks on changed files only instead of full project |
| `PROTECTED_FILES_REGEX` | Lock files + key files | Override protected file regex in `protect-files.sh` — extend for additional file types |

## Boundary check

| Variable | Default | Description |
|---|---|---|
| `BOUNDARY_CHECK_STRICT` | `0` | Set to `1` to fail the build on boundary violations |
| `BOUNDARY_SRC_DIRS` | `src` | Comma-separated source directories to scan for boundary violations |
| `BOUNDARY_INGRESS_REGEX` | JS/TS patterns | Regex for ingress calls — override for Python/Go/Rust (see `scripts/check-boundary-violations.sh`) |
| `BOUNDARY_CORE_GLOB` | `**/core/**` | Glob for core layer files that must not contain ingress calls |
| `BOUNDARY_DOMAIN_GLOB` | `**/domain/**` | Glob for domain layer files that must not contain ingress calls |

## Workflow artifacts

| Variable | Default | Description |
|---|---|---|
| `WORKFLOW_REQUIRE_ARTIFACTS` | `0` | Set to `1` in CI to require all plan/impl/review/test/verify artifacts to be present |
| `WORKFLOW_PLAN_PATH` | `docs/current-plan.md` | Override path for the plan artifact |
| `WORKFLOW_SUMMARY_PATH` | `docs/impl-summary.md` | Override path for the implementation summary artifact |
| `WORKFLOW_REVIEW_PATH` | `docs/review-report.md` | Override path for the review report artifact |
| `WORKFLOW_TEST_PATH` | `docs/test-report.md` | Override path for the test report artifact |
| `WORKFLOW_VERIFY_PATH` | `docs/verify-report.md` | Override path for the verify report artifact |
| `WORKFLOW_SPECS_GLOB` | `docs/specs/*.md` | Override glob for spec artifacts |

## Report quality

| Variable | Default | Description |
|---|---|---|
| `REPORT_QUALITY_REQUIRE_CONTENT` | `0` | Set to `1` in CI to require review/test/verify reports to exist and have content |

## Security scan

| Variable | Default | Description |
|---|---|---|
| `SECURITY_SCAN_REQUIRED` | `0` | Set to `1` to fail if no supported security scanner is found |

## Workflow gates

| Variable | Default | Description |
|---|---|---|
| `WORKFLOW_GATES_SKIP` | `0` | Set to `1` to bypass workflow phase prerequisite checks |
| `WORKFLOW_STATE_PATH` | `.claude/workflow-state.json` | Override path for the workflow state file |
