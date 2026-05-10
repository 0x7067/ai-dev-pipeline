#!/usr/bin/env bash
# release.sh — `release` skill orchestrator (shell layer).
#
# FC/IS placement: SHELL. All I/O, all git mutations, all subprocess calls.
# Pure decisions live in scripts/release/lib/{semver,changelog}-core.sh.
# Untrusted input is parsed at the boundary by parse-changelog.sh and by
# parse_semver before crossing into core.
#
# Interactive contract:
#   AskUserQuestion is a Claude tool, not a shell facility. This orchestrator
#   reaches the two human checkpoints by HALTING with a structured stdout
#   line and a sentinel exit code (75, EX_TEMPFAIL by BSD/sysexits.h):
#
#     RELEASE_HALT: kind=version-confirm proposed=<X.Y.Z> bump=<patch|minor|major> current=<x.y.z>
#     RELEASE_HALT: kind=push-confirm tag=v<X.Y.Z>
#
#   The skill (.claude/skills/release/SKILL.md) instructs Claude to surface
#   each halt via AskUserQuestion and re-invoke this script with:
#
#     RELEASE_RESUME=1
#     RELEASE_ANSWER=approve|reject|pick:<X.Y.Z>      # for version-confirm
#     RELEASE_ANSWER=approve|reject                   # for push-confirm
#
#   plus RELEASE_STATE_FILE pointing at the sidecar file the script wrote
#   on the prior halt so it can pick up where it left off.
#
#   The state sidecar carries a `phase` field that is the SOLE source of
#   truth for which halt this resume answers. The legacy `RELEASE_PHASE`
#   env var is no longer consulted; if set, a deprecation warning is
#   printed and the value is ignored.
#
# Modes:
#   release.sh                 (no args) — fresh run from CWD repo root.
#   RELEASE_RESUME=1 release.sh         — resume from RELEASE_STATE_FILE.
#   release.sh --dry-run               — never mutate files or git refs.

set -Eeuo pipefail

# Initialize early so the EXIT trap can reference these unconditionally even
# if we exit before mktemp runs.
tag_body_file=""
state_file=""
# Set to 1 inside terminal branches that should remove the state sidecar;
# left 0 across version-confirm and push-confirm halts so resume can read it
# (I-tempclean — preservation across halts is INTENTIONAL).
_release_remove_state_on_exit=0

cleanup() {
  local rc=$?
  [[ -n "$tag_body_file" ]] && rm -f "$tag_body_file"
  if (( _release_remove_state_on_exit )) && [[ -n "$state_file" ]]; then
    rm -f "$state_file"
  fi
  return "$rc"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd -P)"
# shellcheck source=scripts/release/lib/semver-core.sh
source "$SCRIPT_DIR/lib/semver-core.sh"
# shellcheck source=scripts/release/lib/changelog-core.sh
source "$SCRIPT_DIR/lib/changelog-core.sh"
# shellcheck source=scripts/release/lib/resume-core.sh
source "$SCRIPT_DIR/lib/resume-core.sh"
STATE_PARSER="$SCRIPT_DIR/parse-release-state.sh"

EX_TEMPFAIL=75

DRY_RUN=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    *) ;;
  esac
done

err()  { printf 'release: ERROR: %s\n' "$*" >&2; }
info() { printf 'release: %s\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { err "$1 is required"; exit 1; }
}

require jq
require git

cd "$REPO_ROOT"

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CHANGELOG="CHANGELOG.md"
PARSER="$SCRIPT_DIR/parse-changelog.sh"

for f in "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$CHANGELOG"; do
  [[ -f "$f" ]] || { err "missing required file: $f"; exit 1; }
done

# Boundary parser: RELEASE_STATE_FILE is untrusted ingress data on resume.
# Accept only absolute paths under $TMPDIR or /tmp/. Fail closed.
parse_state_file_path() {
  local raw="${1:-}"
  local tmpdir="${TMPDIR:-/tmp}"
  local tmpdir_norm="${tmpdir%/}/"
  if [[ -z "$raw" ]]; then
    err "RELEASE_STATE_FILE is empty"
    return 1
  fi
  if [[ "$raw" != /* ]]; then
    err "RELEASE_STATE_FILE='$raw' must be an absolute path"
    return 1
  fi
  if [[ "$raw" == *".."* ]]; then
    err "RELEASE_STATE_FILE='$raw' must not contain '..' segments"
    return 1
  fi
  if [[ "$raw" != "$tmpdir_norm"* && "$raw" != "/tmp/"* ]]; then
    err "RELEASE_STATE_FILE='$raw' must be under \$TMPDIR or /tmp/"
    return 1
  fi
  printf '%s' "$raw"
}

# Halt state sidecar. State is JSON with the resolved decisions so far.
# On resume, parse the supplied path at the boundary before any read.
if [[ "${RELEASE_RESUME:-0}" == "1" ]]; then
  if ! state_file="$(parse_state_file_path "${RELEASE_STATE_FILE:-}")"; then
    exit 1
  fi
else
  state_file="${RELEASE_STATE_FILE:-}"
  if [[ -z "$state_file" ]]; then
    state_file="$(mktemp -t release-state.XXXXXX.json)"
  fi
fi

write_state_phase_a() {
  # Sidecar after Phase A halt — `phase=pending-version-confirm`.
  # I-monotonic-phase: this is only invoked from the fresh-run branch
  # before any answer is known.
  local proposed="$1" bump="$2" current="$3"
  jq -n \
    --arg phase    "pending-version-confirm" \
    --arg proposed "$proposed" \
    --arg bump     "$bump" \
    --arg current  "$current" \
    '{phase:$phase, proposed:$proposed, bump:$bump, current:$current}' \
    > "$state_file"
}

write_state_phase_b_complete() {
  # Sidecar after Phase B mutations + commit + tag succeed — advances
  # `phase` to `phase-b-complete` and pins target_version + tag so the
  # resume into Phase C (push) can dispatch without re-deriving anything.
  local target_version="$1" bump="$2" current="$3"
  jq -n \
    --arg phase   "phase-b-complete" \
    --arg proposed "$target_version" \
    --arg bump    "$bump" \
    --arg current "$current" \
    --arg tv      "$target_version" \
    --arg tag     "v$target_version" \
    '{phase:$phase, proposed:$proposed, bump:$bump, current:$current, target_version:$tv, tag:$tag}' \
    > "$state_file"
}

# NOTE on state-file lifetime (I-tempclean):
# emit_halt_version and emit_halt_push intentionally PRESERVE the state file
# across the halt — the next invocation (resume) must read it. The cleanup
# trap only removes it when a terminal branch sets
# _release_remove_state_on_exit=1.
emit_halt_version() {
  local proposed="$1" bump="$2" current="$3"
  write_state_phase_a "$proposed" "$bump" "$current"
  printf 'RELEASE_HALT: kind=version-confirm proposed=%s bump=%s current=%s\n' \
    "$proposed" "$bump" "$current"
  printf 'RELEASE_STATE_FILE=%s\n' "$state_file"
  exit "$EX_TEMPFAIL"
}

emit_halt_push() {
  local tag="$1"
  printf 'RELEASE_HALT: kind=push-confirm tag=%s\n' "$tag"
  printf 'RELEASE_STATE_FILE=%s\n' "$state_file"
  exit "$EX_TEMPFAIL"
}

# ---------------------------------------------------------------------------
# Phase A: derive proposal, halt for version confirmation.
# ---------------------------------------------------------------------------
if [[ "${RELEASE_RESUME:-0}" != "1" ]]; then
  # Read current version from plugin.json and parse it via boundary
  # (I-currentread: a fresh run reads it here exactly once; resume reads
  # it from the state sidecar via read_state_field current).
  current_version="$(jq -r '.version' "$PLUGIN_JSON")"
  if ! parse_semver "$current_version" >/dev/null; then
    err "current $PLUGIN_JSON .version='$current_version' is not a release SemVer"
    exit 1
  fi

  # Cross-manifest invariant pre-check (Phase A only — resume path trusts
  # the state sidecar, which was written after this check on the prior run).
  mp_version="$(jq -r '.plugins[0].version' "$MARKETPLACE_JSON")"
  if [[ "$current_version" != "$mp_version" ]]; then
    err "pre-release lockstep broken: $PLUGIN_JSON=$current_version vs $MARKETPLACE_JSON=$mp_version"
    exit 1
  fi


  # Decision D5: clean working tree precondition (no commits will land on
  # an unclean tree).
  if [[ -n "$(git status --porcelain)" ]]; then
    err "working tree is not clean. Commit or stash before releasing."
    git status --short >&2
    exit 1
  fi

  # Validate CHANGELOG topmost section parses cleanly.
  if ! "$PARSER" --check "$CHANGELOG"; then
    err "CHANGELOG.md failed to parse — fix the topmost section first"
    exit 1
  fi

  topmost_label="$("$PARSER" --label "$CHANGELOG")"

  case "$topmost_label" in
    Unreleased)
      ;;
    *)
      # D4: nothing-to-release — abort with diagnostic.
      err "nothing to release: CHANGELOG topmost section is [$topmost_label], no [Unreleased] block above it"
      exit 1
      ;;
  esac

  bump="$("$PARSER" "$CHANGELOG" | infer_bump_from_changelog)"
  proposed="$(next_version "$current_version" "$bump")"

  # Refuse to propose an already-tagged version.
  if git rev-parse "v$proposed" >/dev/null 2>&1; then
    err "tag v$proposed already exists; refusing to re-tag"
    exit 1
  fi

  emit_halt_version "$proposed" "$bump" "$current_version"
fi

# ---------------------------------------------------------------------------
# Resume dispatch: parse state at boundary, decide branch in core, then run.
# ---------------------------------------------------------------------------
if [[ ! -f "$state_file" ]]; then
  err "RELEASE_RESUME=1 but RELEASE_STATE_FILE missing or unreadable"
  exit 1
fi

# Deprecation: RELEASE_PHASE is no longer consulted. Warn if a caller still
# sets it so the migration is visible without breaking the resume.
if [[ -n "${RELEASE_PHASE:-}" ]]; then
  info "(deprecated) RELEASE_PHASE='$RELEASE_PHASE' is ignored; phase is read from the state file"
fi

# Boundary parse of the untrusted sidecar.
if ! state_typed="$("$STATE_PARSER" "$state_file")"; then
  exit 1
fi

state_phase=""
state_bump=""
state_current=""
state_proposed=""
state_tag=""
while IFS=$'\t' read -r _k _v; do
  case "$_k" in
    phase)    state_phase="$_v" ;;
    bump)     state_bump="$_v" ;;
    current)  state_current="$_v" ;;
    proposed) state_proposed="$_v" ;;
    tag)      state_tag="$_v" ;;
    # target_version is validated by the parser; we use $state_tag downstream.
  esac
done <<< "$state_typed"

answer="${RELEASE_ANSWER:-}"
action="$(release_resume_decide "$state_phase" "$answer")"

case "$action" in
  error:unknown-phase)
    err "state file recorded unknown phase '$state_phase'"
    exit 1
    ;;
  error:ambiguous-answer)
    case "$state_phase" in
      pending-version-confirm)
        err "ambiguous RELEASE_ANSWER for version-confirm: '$answer' (expected approve|reject|pick:<X.Y.Z>)"
        ;;
      phase-b-complete)
        err "ambiguous RELEASE_ANSWER for push-confirm: '$answer' (expected approve|reject)"
        ;;
    esac
    exit 1
    ;;
  reject-pre-mutation)
    info "release rejected at version-confirm gate; no changes made"
    _release_remove_state_on_exit=1
    exit 0
    ;;
  reject-post-mutation)
    info "push declined; commit + tag remain local ($state_tag)"
    _release_remove_state_on_exit=1
    exit 0
    ;;
  push)
    # I-no-retag: no mutations on this branch. Verify the tag actually exists
    # before pushing — if the state claims phase-b-complete but the tag is
    # absent, the local repo has been tampered with; fail closed.
    if ! git rev-parse "$state_tag" >/dev/null 2>&1; then
      err "state claims phase-b-complete but tag $state_tag absent; manual recovery required"
      exit 1
    fi
    info "pushing HEAD and tag $state_tag"
    if (( DRY_RUN )); then
      info "(dry-run) skipping git push"
    else
      git push && git push origin "$state_tag"
    fi
    _release_remove_state_on_exit=1
    exit 0
    ;;
  run-phase-b)
    : # fall through to Phase B below
    ;;
  *)
    err "internal: unrecognized resume action '$action'"
    exit 1
    ;;
esac

# At this point: action=run-phase-b, phase=pending-version-confirm.
proposed="$state_proposed"
bump="$state_bump"
current_version="$state_current"

case "$answer" in
  approve)
    target_version="$proposed"
    ;;
  pick:*)
    candidate="${answer#pick:}"
    if ! parse_semver "$candidate" >/dev/null; then
      err "ambiguous answer: pick:'$candidate' is not a release SemVer"
      exit 1
    fi
    cmp="$(compare_semver "$candidate" "$current_version")"
    if [[ "$cmp" != "1" ]]; then
      err "pick:$candidate is not strictly greater than current $current_version"
      exit 1
    fi
    target_version="$candidate"
    ;;
  *)
    # Unreachable: release_resume_decide already filtered ambiguous answers.
    err "internal: unexpected answer '$answer' at run-phase-b"
    exit 1
    ;;
esac

if git rev-parse "v$target_version" >/dev/null 2>&1; then
  err "tag v$target_version already exists; refusing to re-tag"
  exit 1
fi

# ---------------------------------------------------------------------------
# Phase B continued: gates → mutations → commit → tag → halt for push.
# ---------------------------------------------------------------------------

# Re-check clean tree just before mutating (defensive).
if [[ -n "$(git status --porcelain)" ]]; then
  err "working tree became dirty between phases; aborting"
  exit 1
fi

run_gate() {
  local label="$1"; shift
  info "gate: $label"
  if (( DRY_RUN )); then
    info "(dry-run) skipping: $*"
    return 0
  fi
  if ! "$@"; then
    err "gate failed: $label"
    exit 1
  fi
}

run_gate "validate-claude-config" bash scripts/validate-claude-config.sh
run_gate "verification-gates"     bash scripts/run-verification-gates.sh
run_gate "smoke-bootstrap"        bash scripts/smoke-bootstrap.sh

# ---- Mutations -------------------------------------------------------------
release_date="$(date -u +%Y-%m-%d)"

# Capture the just-released bullet body BEFORE rewriting CHANGELOG so the
# tag annotation can reuse it (D3).
tag_body_file="$(mktemp -t release-tag-body.XXXXXX)"
{
  printf 'Release v%s\n\n' "$target_version"
  # Strip "section_label" + "section_date" lines, render entries.
  "$PARSER" "$CHANGELOG" | awk -F'\t' '
    $1 == "entry" { printf "- [%s] %s\n", $2, $3 }
  '
} > "$tag_body_file"

bump_json_version() {
  local file="$1"
  local tmp
  tmp="$(mktemp -t plugin-json.XXXXXX.json)"
  jq --arg v "$target_version" '.version = $v' "$file" > "$tmp"
  mv "$tmp" "$file"
}

bump_marketplace_version() {
  local file="$1"
  local tmp
  tmp="$(mktemp -t marketplace-json.XXXXXX.json)"
  jq --arg v "$target_version" '.plugins[0].version = $v' "$file" > "$tmp"
  mv "$tmp" "$file"
}

rewrite_changelog() {
  # Replace the topmost `## [Unreleased]` line with `## [X.Y.Z] - DATE`,
  # then prepend a fresh empty `## [Unreleased]` section above it (D2).
  local tmp
  tmp="$(mktemp -t changelog.XXXXXX.md)"
  awk -v ver="$target_version" -v date="$release_date" '
    BEGIN { rewritten = 0 }
    {
      if (!rewritten && $0 ~ /^## \[Unreleased\][[:space:]]*$/) {
        print "## [Unreleased]"
        print ""
        print "## [" ver "] - " date
        rewritten = 1
        next
      }
      print
    }
  ' "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
}

# I-atomic: any non-zero exit inside this mutation block aborts before
# commit/tag (set -e) and prints a recovery hint via the ERR trap.
mutation_failed() {
  err "mutation aborted; recover with: git checkout -- $PLUGIN_JSON $MARKETPLACE_JSON $CHANGELOG"
}
trap mutation_failed ERR

if (( DRY_RUN )); then
  info "(dry-run) skipping manifest + CHANGELOG mutations"
else
  bump_json_version       "$PLUGIN_JSON"
  bump_marketplace_version "$MARKETPLACE_JSON"
  rewrite_changelog
fi

# ---- Commit + tag ----------------------------------------------------------
if (( DRY_RUN )); then
  info "(dry-run) skipping git commit + tag"
else
  git add "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$CHANGELOG"
  git commit -m "chore(release): v$target_version"
  git tag -a "v$target_version" -F "$tag_body_file"
fi

# Mutation block succeeded; drop the recovery-hint trap.
trap - ERR

rm -f "$tag_body_file"
tag_body_file=""

# Advance phase to `phase-b-complete` BEFORE emitting the push-confirm halt
# so the resume invocation observes the committed-and-tagged state (I-monotonic-phase).
write_state_phase_b_complete "$target_version" "$bump" "$current_version"

# Halt for push approval. The skill instructs Claude to re-invoke with
# RELEASE_RESUME=1 and RELEASE_ANSWER=approve|reject; phase is read from the
# state sidecar.
emit_halt_push "v$target_version"
