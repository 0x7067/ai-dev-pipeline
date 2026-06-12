from __future__ import annotations

from aidp.models import ContextPack, RunContract, WorkPlan


def render_worker_brief(
    *,
    run_id: str,
    contract: RunContract,
    context: ContextPack,
    plan: WorkPlan,
) -> str:
    lines = [
        "# Agent Work Packet",
        "",
        f"Run: {run_id}",
        f"Objective: {contract.objective}",
        f"Risk: {contract.risk}",
        "Read spans only; do not reread whole files.",
        "",
        "## Constraints",
    ]
    if contract.constraints:
        lines.extend(f"- {item}" for item in contract.constraints)
    else:
        lines.append("- none")

    lines.extend(["", "## Context Pointers"])
    if context.sources:
        for source in context.sources:
            span_text = ", ".join(source.spans) if source.spans else "all"
            lines.append(f"- {source.path}:{span_text} ({source.purpose})")
    else:
        lines.append("- none")
    if context.omitted:
        lines.append("- omitted: " + "; ".join(context.omitted))

    lines.extend(["", "## Tasks"])
    for index, task in enumerate(plan.tasks, start=1):
        lines.append(f"{index}. {task.title}")
        if task.expected_paths:
            lines.append("   - expected paths: " + ", ".join(f"`{path}`" for path in task.expected_paths))
        if task.test_first:
            lines.append("   - test first: " + "; ".join(task.test_first))
        if task.proof_commands:
            lines.append("   - proof: " + "; ".join(f"`{command}`" for command in task.proof_commands))

    lines.extend(["", "## Review Focus"])
    if plan.review_focus:
        lines.extend(f"- {item}" for item in plan.review_focus)
    else:
        lines.append("- direct evidence for every done-when item")

    lines.extend(["", "## Commands"])
    if context.commands:
        lines.extend(f"- `{command}`" for command in context.commands)
    else:
        lines.append("- no project commands detected")
    lines.append(f"- Run `aidp prove {run_id}` before `aidp finish {run_id}`.")

    return "\n".join(lines) + "\n"


def render_agent_prompt(*, run_id: str, work_packet_path: str, work_packet: str) -> str:
    lines = [
        f"You are executing AIDP run {run_id}.",
        "",
        f"Read `{work_packet_path}` first.",
        "Execute the work packet exactly.",
        "Keep context bounded to listed spans unless a span is insufficient.",
        "Write tests first for behavior changes; keep edits scoped to the objective.",
        "Stop before destructive actions, secrets, spending, production changes, history rewrites, or force-pushes.",
        f"After implementation, run `aidp prove {run_id}` and `aidp finish {run_id}`.",
        "",
        "## Work Packet",
        "",
        work_packet.rstrip(),
        "",
    ]
    return "\n".join(lines)
