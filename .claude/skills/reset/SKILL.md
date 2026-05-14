---
name: reset
description: Clear stale ai-dev-pipeline workflow state so the next `/ship` invocation starts a fresh phase sequence. Triggers on "reset workflow", "/reset", "clear workflow state", or whenever the workflow-gate hook blocks because an abandoned state file from a prior session lingers. Does not delete run artifacts under `docs/aidp/runs/`; only clears the active-run pointer and the per-run state file.
---

# Reset

Clears the workflow-state pointer (`.claude/workflow-state/active`) and the
per-run state file it points to, so the workflow-gate hook stops enforcing a
stale phase profile. Run artifacts under `docs/aidp/runs/<id>/` are
preserved — those are the audit trail.

## When to use

- The `workflow-gate.sh` hook blocks an `Agent` invocation because a prior
  session left a half-completed state file behind.
- You want to abandon the current `/ship` run and start fresh.
- An `implementer` / `reviewer` / `tester` / `verifier` agent falls back to
  `general-purpose` despite no live `/ship` run.

## When NOT to use

- During a live `/ship` run you intend to resume. Use the in-band
  `[gate-bypass: <reason>]` token instead (see
  `.claude/rules/release-and-verification.md`).
- To wipe historical run artifacts. Use `bash scripts/prune-runs.sh` for
  retention-based cleanup.

## Steps

1. Resolve the project root (must be the consumer repo, not the plugin
   checkout). The pipeline anchors workflow state under
   `${AIDP_PROJECT_ROOT}/.claude/workflow-state/`.

   ```sh
   source "${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT not set}/scripts/lib/project-root.sh"
   proj_root="$(aidp_resolve_project_root)" || {
     echo "reset: ERROR: could not resolve project root" >&2
     exit 2
   }
   ```

2. Read the active pointer to identify the per-run state file:

   ```sh
   active_pointer="${proj_root}/.claude/workflow-state/active"
   if [ -f "$active_pointer" ]; then
     active_id="$(cat "$active_pointer")"
   fi
   ```

3. Remove the active pointer and the per-run state file (if any). Run
   artifacts under `docs/aidp/runs/${active_id}/` are NOT touched:

   ```sh
   rm -f "$active_pointer"
   if [ -n "${active_id:-}" ]; then
     rm -f "${proj_root}/.claude/workflow-state/${active_id}.json"
   fi
   ```

4. Report:

   ```sh
   printf '✓ workflow state cleared (was run=%s)\n' "${active_id:-<none>}"
   ```

## Output

- `✓ workflow state cleared (was run=<id>)` on success.
- `reset: ERROR: …` on failure (project root unresolvable, permission
  denied). Exit non-zero.

## Audit

This action is not logged to `decisions.jsonl` because it operates outside
any specific run. The `gate-bypass.log` is also untouched. If audit is
required for a reset, record it manually before invoking.
