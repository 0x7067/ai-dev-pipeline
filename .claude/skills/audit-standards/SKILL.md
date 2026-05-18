---
name: audit-standards
description: Use when the user invokes /audit standards (with or without --bucket). Orchestrates the full pattern-discovery pipeline — tool pre-flight, git verification, extraction, clustering, confidence scoring, GC, pattern-file writing, and the AskUserQuestion-driven promotion loop via the discoverer agent.
---

# /audit standards — Pattern Discovery Skill

## Purpose

Scan the consumer repo for recurring structural conventions across code roles
(tests, HTTP handlers, background jobs, CLI entrypoints, data-access, utilities).
Surface high-confidence patterns to the user for optional promotion to
`.claude/rules/<name>.md`.

## Pre-flight checks (hard fail)

Before any scan work:

1. Verify `ast-grep` is available: `ast-grep --version` → if not found, print install hint and abort.
   - macOS: `brew install ast-grep`
   - Rust: `cargo install ast-grep --locked`
2. Verify `ctags` (universal-ctags) is available: `ctags --version` → if not found, print install hint and abort.
   - macOS: `brew install universal-ctags`
   - Ubuntu: `apt-get install universal-ctags`
3. Verify git checkout: `git rev-parse --git-dir` → hard fail if not a git repo.
4. If `--bucket <name>` was passed, validate against `^[a-z0-9_-]+$` before proceeding.

## Scan pipeline

```
git ls-files -z
  └─ bucketize_paths (core/bucket.py, first-match-wins)
       └─ skip buckets with < AIDP_DISCOVER_BUCKET_MIN files (default 5)
            └─ extract.sh (ast-grep + ctags, NUL-delimited paths)
                 └─ boundary.py (parse Match + Symbol records)
                      └─ features.py (extract FileFeatures per file)
                           └─ cluster.py (cluster per bucket → Pattern list)
                                └─ confidence.py (score + threshold filter)
                                     └─ report.py (render pattern docs)
                                          └─ GC + write .claude/discovered-patterns/
                                               └─ discoverer agent (promotion loop)
```

## Configuration

| Variable                    | Default | CLI override     | Description                        |
|-----------------------------|---------|------------------|------------------------------------|
| `AIDP_DISCOVER_THRESHOLD`   | 70      | `--threshold`    | Confidence threshold (%)           |
| `AIDP_DISCOVER_BUCKET_MIN`  | 5       | `--min-bucket`   | Min files to process a bucket      |
| `AIDP_DISCOVER_LANGS`       | (all)   | `--langs`        | Comma-sep language filter          |

## Bucketing rules

Applied in precedence order (first match wins). Unbucketed files are skipped.

| Bucket           | Path patterns                                               | Allowed kinds      |
|------------------|-------------------------------------------------------------|--------------------|
| tests            | `**/test/**`, `**/tests/**`, `**/*.test.*`, `**/*_test.*`, `**/*.spec.*` | all     |
| http-handlers    | `**/api/**`, `**/handlers/**`, `**/routes/**`, `**/controllers/**` | function, method |
| background-jobs  | `**/jobs/**`, `**/workers/**`, `**/tasks/**`               | function, method   |
| cli-entrypoints  | `**/cli/**`, `**/cmd/**`, `**/bin/**`                      | function, method   |
| data-access      | `**/db/**`, `**/models/**`, `**/repository/**`             | class, function    |
| utilities        | `**/lib/**`, `**/utils/**`, `**/helpers/**`                | function           |

## Confidence bands

| Band   | Frequency  | Behavior at default threshold (70%)  |
|--------|------------|--------------------------------------|
| strong | ≥ 80%      | surviving (shown to user)            |
| weak   | 60–79%     | surviving if ≥ threshold             |
| noise  | < 60%      | always suppressed                    |

## GC

Before writing new pattern files:
1. Compute the set of pattern_ids from this run's surviving patterns.
2. Delete any `.claude/discovered-patterns/<id>.md` file whose id is NOT in the surviving set.
   - If `--bucket <name>` was passed, only delete files for that bucket.
3. Write new/updated pattern files from `docs/templates/discovered-pattern-template.md`.

## Promotion loop

Invoke the `discoverer` agent after GC + write. Pass `RUN_ID` and `RUN_DIR`.
The discoverer drives the `AskUserQuestion` loop and logs all decisions.

## Output

- `.claude/discovered-patterns/<pattern_id converted to filename>.md` — one file per surviving pattern.
- Approved patterns → `.claude/rules/<name>.md`.
- `${RUN_DIR}/decisions.jsonl` — promotion decisions.

## .gitignore guidance

`.claude/discovered-patterns/` should be gitignored in consumer repos (it is
ephemeral scan output). `scripts/validate-claude-config.sh` warns if it is not
gitignored when the directory exists on disk.
