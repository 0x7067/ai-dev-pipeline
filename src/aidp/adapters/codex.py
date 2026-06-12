from __future__ import annotations


def render_agents_md() -> str:
    return """# AGENTS.md

## AIDP v2

Use the typed AIDP kernel as the project workflow surface:

- Start work with `aidp "<objective>" --run-id <short-id> --proof-command "<cmd>"`.
- Read spans from `.aidp/runs/<run-id>/work.md`; do not copy whole source files into chat.
- Implement the task slice, then run `aidp check <run-id>` and `aidp prove <run-id>`.
- Finish with `aidp finish <run-id>` and report the status, proven items, unresolved items, and log paths.

## Operating Rules

- Keep context small: prefer paths, line spans, symbols, and command logs over pasted file bodies.
- Plan before multi-file or risky edits, but keep the plan tied to the typed run artifacts.
- Write tests before behavior changes. If no automated test is practical, add the proof command before implementation.
- Treat a green command as evidence only for the requirement it directly proves.
- Ask before destructive actions, force/history changes, secrets/auth changes, spending, or production operations.
- Preserve unrelated worktree changes.
- Use subagents when independent review/research can run in parallel without blocking the next local step.

## Verification

- `aidp prove <run-id>` records command evidence under `.aidp/runs/<run-id>/logs/`.
- `aidp check <run-id>` validates typed artifacts; `aidp finish <run-id>` reruns that check before completion audit.
- Do not claim done while `aidp finish <run-id>` reports unresolved items.
- If you add or change AIDP itself, run `uv run pytest tests/aidp -q`.
"""
