---
name: release
description: Use when the user says "cut a release", "bump tag", "tag v…", "ship a release", "release this", or otherwise asks to publish a new version. Parses CHANGELOG to propose a SemVer bump, runs the verification + validator + smoke gate trio, syncs `plugin.json` + `.claude-plugin/marketplace.json`, rewrites the CHANGELOG header, commits, and creates an annotated tag. Halts twice for explicit human approval (proposed version, push). Do not invoke for routine commits or non-release work.
---

# Release

This skill automates the per-version release ritual without coupling to
`/ship`. It is **skill-only** — there is no slash command — and it shells
out to the canonical gate runners rather than re-implementing them.

## When to invoke

User says any of: "cut a release", "release v…", "bump the tag", "tag this",
"ship a release", "release this", "publish a new version".

Do NOT invoke for: routine commits, in-progress work, hotfixes that have
not yet landed in `[Unreleased]`, or any request that is just about
verification (use `/ship` or `/audit`).

## What it does (deterministic order)

1. Asserts a clean working tree (`git status --porcelain` empty).
2. Parses `CHANGELOG.md` via `scripts/release/parse-changelog.sh` (boundary
   parser; rejects malformed headers / unknown labels).
3. Infers the next bump (`patch | minor | major`) from the topmost
   `[Unreleased]` section using
   `scripts/release/lib/changelog-core.sh::infer_bump_from_changelog`.
4. **HALT 1** — proposes the new version. See "Interactive contract" below.
5. After approval, runs the gate trio (any non-zero aborts before any
   write):
   - `scripts/validate-claude-config.sh`
   - `scripts/run-verification-gates.sh`
   - `scripts/smoke-bootstrap.sh`
6. Updates `.claude-plugin/plugin.json` and
   `.claude-plugin/marketplace.json` to the new version (lockstep
   invariant I1).
7. Rewrites `CHANGELOG.md`: replaces `## [Unreleased]` with
   `## [X.Y.Z] - YYYY-MM-DD`, then prepends a fresh empty
   `## [Unreleased]` block above it (Keep-a-Changelog convention).
8. Commits the three files with `chore(release): vX.Y.Z`.
9. Creates an annotated tag `vX.Y.Z` whose message body is the
   bullet-list of the just-released CHANGELOG section, prefixed with
   `Release vX.Y.Z`.
10. **HALT 2** — asks whether to `git push` HEAD and the new tag.

## Interactive contract (important)

`AskUserQuestion` is a Claude tool, not a shell facility. The orchestrator
script `scripts/release/release.sh` therefore reaches each human checkpoint
by **halting** with a structured stdout line and a sentinel exit code
(`75`, EX_TEMPFAIL).

When you (Claude) see a halt, surface it as `AskUserQuestion`, then
re-invoke the script with the user's answer in environment variables.

### Halt 1: version-confirm

Stdout includes:
```
RELEASE_HALT: kind=version-confirm proposed=<X.Y.Z> bump=<patch|minor|major> current=<x.y.z>
RELEASE_STATE_FILE=/tmp/release-state.XXXX.json
```

Surface via `AskUserQuestion` with:
- Option 1: `Approve <X.Y.Z> (Recommended)` — "Cut release at the
  inferred bump."
- Option 2: `Reject` — "Abort the release; nothing changes."
- Free-text "Other": user types their preferred version (e.g.
  `1.2.0`); pass it through as `pick:<value>`.

Resume by invoking:
```
RELEASE_RESUME=1 \
RELEASE_STATE_FILE=<state-file-from-halt> \
RELEASE_ANSWER=approve|reject|pick:X.Y.Z \
bash scripts/release/release.sh
```

### Halt 2: push-confirm

After the commit + tag are created locally, stdout includes:
```
RELEASE_HALT: kind=push-confirm tag=v<X.Y.Z>
RELEASE_STATE_FILE=/tmp/release-state.XXXX.json
```

Surface via `AskUserQuestion` with:
- Option 1: `Approve (Recommended)` — "Push HEAD and the new tag."
- Option 2: `Reject` — "Keep commit + tag local; user pushes manually."

(Per `.claude/rules/release-and-verification.md` HITL invariant 8, the
release gate has no `edit` option.)

Resume by invoking:
```
RELEASE_RESUME=1 \
RELEASE_PHASE=push \
RELEASE_STATE_FILE=<state-file-from-halt> \
RELEASE_ANSWER=approve|reject \
bash scripts/release/release.sh
```

## Failure handling

- Unknown CHANGELOG label or malformed header → parser rejects, the
  orchestrator aborts with the parser's diagnostic. No mutations happen.
- Working tree dirty at start → abort with diagnostic.
- Tag `vX.Y.Z` already exists → abort before any commit.
- Gate failure → abort before any commit (working tree restored to
  pre-gate state because nothing was written yet).
- Reject at Halt 1 → no-op; tree unchanged.
- Reject at Halt 2 → commit + tag remain local; the user is told and
  may `git push` (or `git tag -d` to roll back) manually.

## FC/IS placement

- **Core (pure):** `scripts/release/lib/semver-core.sh` (`parse_semver`,
  `format_semver`, `next_version`, `compare_semver`),
  `scripts/release/lib/changelog-core.sh` (`infer_bump_from_changelog`).
- **Boundary:** `scripts/release/parse-changelog.sh` (typed records,
  fail-closed reject set).
- **Shell:** `scripts/release/release.sh` (file mutations, `git add /
  commit / tag / push`, gate dispatch, halt protocol).

## Tests

- `tests/scripts/test-changelog-parser.sh` — accept + reject set.
- `tests/scripts/test-semver-core.sh` — property: monotonicity +
  round-trip.
- `tests/scripts/test-release-version-lockstep.sh` — contract: after a
  simulated dry release, `plugin.json` and `marketplace.json` move
  together and `check-plugin-version-sync.sh` exits 0.
