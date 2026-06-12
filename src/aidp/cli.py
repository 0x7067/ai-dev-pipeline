from __future__ import annotations

import argparse
import json
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path

from aidp import __version__
from aidp.adapters.codex import render_agents_md
from aidp.check import check_run
from aidp.context_pack import build_context_pack
from aidp.cutover import build_cutover_audit
from aidp.detect import detect_project
from aidp.finish import audit_completion
from aidp.gates import run_gate
from aidp.models import ContextPack, EvidenceBundle, PlanTask, RunContract, WorkPlan, parse_artifact
from aidp.work import render_agent_prompt, render_worker_brief

COMMANDS = {"adapter", "agent", "check", "cutover", "doctor", "plan", "work", "prove", "finish", "self-test", "start"}


def main(argv: list[str] | None = None) -> int:
    argv = _inject_default_start(argv)
    parser = argparse.ArgumentParser(prog="aidp")
    parser.add_argument("--root", default=".", help="project root")
    parser.add_argument("--version", action="store_true", help="print version and exit")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("doctor", help="inspect the current project")
    subparsers.add_parser("cutover", help="audit retired surface removal readiness")
    subparsers.add_parser("self-test", help="run hermetic v2 pipeline scenarios")

    adapter_parser = subparsers.add_parser("adapter", help="generate agent-surface adapters")
    adapter_subparsers = adapter_parser.add_subparsers(dest="adapter_name", required=True)
    codex_parser = adapter_subparsers.add_parser("codex", help="render Codex AGENTS.md guidance")
    codex_parser.add_argument("--output")
    codex_parser.add_argument("--force", action="store_true")

    plan_parser = subparsers.add_parser("plan", help="create typed run artifacts")
    plan_parser.add_argument("objective")
    plan_parser.add_argument("--run-id", required=True)
    plan_parser.add_argument("--proof-command", action="append", default=[])

    start_parser = subparsers.add_parser("start", help=argparse.SUPPRESS)
    start_parser.add_argument("objective")
    start_parser.add_argument("--run-id")
    start_parser.add_argument("--proof-command", action="append", default=[])

    prove_parser = subparsers.add_parser("prove", help="run proof commands")
    prove_parser.add_argument("run_id")

    work_parser = subparsers.add_parser("work", help="write a compact worker brief")
    work_parser.add_argument("run_id")

    agent_parser = subparsers.add_parser("agent", help="print an executable agent prompt")
    agent_parser.add_argument("run_id")

    check_parser = subparsers.add_parser("check", help="validate typed run artifacts")
    check_parser.add_argument("run_id")

    finish_parser = subparsers.add_parser("finish", help="audit completion evidence")
    finish_parser.add_argument("run_id")

    args = parser.parse_args(argv)
    root = Path(args.root)
    if args.version:
        print(__version__)
        return 0
    if args.command == "doctor":
        return _doctor(root)
    if args.command == "cutover":
        return _cutover(root)
    if args.command == "self-test":
        return _self_test()
    if args.command == "adapter":
        return _adapter(args.adapter_name, args.output, args.force)
    if args.command == "plan":
        return _plan(root, args.objective, args.run_id, tuple(args.proof_command))
    if args.command == "start":
        return _start(root, args.objective, args.run_id or _new_run_id(), tuple(args.proof_command))
    if args.command == "prove":
        return _prove(root, args.run_id)
    if args.command == "work":
        return _work(root, args.run_id)
    if args.command == "agent":
        return _agent(root, args.run_id)
    if args.command == "check":
        return _check(root, args.run_id)
    if args.command == "finish":
        return _finish(root, args.run_id)
    parser.print_help()
    return 2


def _doctor(root: Path) -> int:
    profile = detect_project(root)
    payload = {
        "status": "ok",
        "root": str(profile.root),
        "languages": list(profile.languages),
        "package_manager": profile.package_manager,
        "commands": {key: list(value) for key, value in profile.commands.items()},
    }
    print(json.dumps(payload, sort_keys=True))
    return 0


def _self_test() -> int:
    from aidp.selftest import run_self_test

    payload = run_self_test()
    _print_json(payload)
    return 0 if payload["status"] == "pass" else 1


def _cutover(root: Path) -> int:
    _print_json(build_cutover_audit(root))
    return 0


def _adapter(adapter_name: str, output: str | None, force: bool) -> int:
    if adapter_name != "codex":
        print(f"unknown adapter: {adapter_name}", file=sys.stderr)
        return 2
    content = render_agents_md()
    if output is None:
        print(content, end="")
        return 0
    target = Path(output)
    if target.exists() and not force:
        print(f"adapter: {target} already exists; pass --force to overwrite", file=sys.stderr)
        return 1
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    _print_json({"status": "written", "path": str(target)})
    return 0


def _plan(root: Path, objective: str, run_id: str, proof_commands: tuple[str, ...]) -> int:
    run_dir = _create_run(root, objective, run_id, proof_commands)
    _append_event(run_dir, {"event": "planned", "run_id": run_id, "objective": objective})
    _print_json({"run_id": run_id, "run_dir": str(run_dir), "status": "planned"})
    return 0


def _start(root: Path, objective: str, run_id: str, proof_commands: tuple[str, ...]) -> int:
    run_dir = _create_run(root, objective, run_id, proof_commands)
    work_path = _write_work_packet(run_dir, run_id)
    _append_event(run_dir, {"event": "ready", "run_id": run_id, "objective": objective, "work_packet": str(work_path)})
    _print_json({"run_id": run_id, "run_dir": str(run_dir), "status": "ready", "work_packet": str(work_path)})
    return 0


def _create_run(root: Path, objective: str, run_id: str, proof_commands: tuple[str, ...]) -> Path:
    run_dir = _run_dir(root, run_id)
    run_dir.mkdir(parents=True, exist_ok=True)

    contract = RunContract(
        objective=objective,
        done_when=("proof",),
        risk="low",
    )
    context = build_context_pack(root=root, objective=objective)
    plan = WorkPlan(
        tasks=(
            PlanTask(
                title="proof",
                expected_paths=(),
                test_first=(),
                proof_commands=proof_commands,
            ),
        ),
        review_focus=("completion evidence",),
    )

    _write_json(run_dir / "contract.json", contract.to_dict())
    _write_json(run_dir / "context.json", context.to_dict())
    _write_json(run_dir / "plan.json", plan.to_dict())
    return run_dir


def _prove(root: Path, run_id: str) -> int:
    run_dir = _run_dir(root, run_id)
    plan = parse_artifact(_read_json(run_dir / "plan.json"))
    if not isinstance(plan, WorkPlan):
        raise ValueError("plan.json is not a plan artifact")

    commands = []
    for task in plan.tasks:
        for command in task.proof_commands:
            commands.append(command)

    evidence_commands = []
    for command in commands:
        evidence_commands.append(
            run_gate(
                label="proof",
                command=tuple(shlex.split(command)),
                cwd=root,
                log_dir=run_dir / "logs",
                timeout_seconds=600,
            )
        )

    verdict = "pass" if evidence_commands and all(item.exit_code == 0 for item in evidence_commands) else "fail"
    evidence = EvidenceBundle(
        commands=tuple(evidence_commands),
        changed_files=(),
        review_results=(),
        unresolved_risks=(),
        verdict=verdict,
    )
    _write_json(run_dir / "evidence.json", evidence.to_dict())
    _append_event(run_dir, {"event": "proved", "run_id": run_id, "verdict": evidence.verdict})
    _print_json({"run_id": run_id, "run_dir": str(run_dir), "status": evidence.verdict})
    return 0 if evidence.verdict == "pass" else 1


def _work(root: Path, run_id: str) -> int:
    run_dir = _run_dir(root, run_id)
    brief_path = _write_work_packet(run_dir, run_id)
    _append_event(run_dir, {"event": "work", "run_id": run_id, "work_packet": str(brief_path)})
    _print_json(
        {
            "run_id": run_id,
            "run_dir": str(run_dir),
            "status": "ready",
            "work_packet": str(brief_path),
        }
    )
    return 0


def _agent(root: Path, run_id: str) -> int:
    run_dir = _run_dir(root, run_id)
    work_path = _write_work_packet(run_dir, run_id)
    prompt = render_agent_prompt(
        run_id=run_id,
        work_packet_path=f".aidp/runs/{run_id}/work.md",
        work_packet=work_path.read_text(encoding="utf-8"),
    )
    agent_path = run_dir / "agent.md"
    agent_path.write_text(prompt, encoding="utf-8")
    _append_event(run_dir, {"event": "agent", "run_id": run_id, "agent_prompt": str(agent_path)})
    print(prompt, end="")
    return 0


def _check(root: Path, run_id: str) -> int:
    result = check_run(root, run_id)
    _print_json(
        {
            "run_id": run_id,
            "status": result.status,
            "checked": list(result.checked),
            "errors": list(result.errors),
        }
    )
    return 0 if result.status == "pass" else 1


def _write_work_packet(run_dir: Path, run_id: str) -> Path:
    contract = parse_artifact(_read_json(run_dir / "contract.json"))
    context = parse_artifact(_read_json(run_dir / "context.json"))
    plan = parse_artifact(_read_json(run_dir / "plan.json"))
    if not isinstance(contract, RunContract):
        raise ValueError("contract.json is not a contract artifact")
    if not isinstance(context, ContextPack):
        raise ValueError("context.json is not a context artifact")
    if not isinstance(plan, WorkPlan):
        raise ValueError("plan.json is not a plan artifact")

    brief_path = run_dir / "work.md"
    brief_path.write_text(
        render_worker_brief(run_id=run_id, contract=contract, context=context, plan=plan),
        encoding="utf-8",
    )
    return brief_path


def _finish(root: Path, run_id: str) -> int:
    run_dir = _run_dir(root, run_id)
    check = check_run(root, run_id)
    if check.status != "pass":
        _append_event(run_dir, {"event": "finished", "run_id": run_id, "status": "fail"})
        _print_json(
            {
                "run_id": run_id,
                "run_dir": str(run_dir),
                "status": "fail",
                "proven": [],
                "unresolved": list(check.errors),
            }
        )
        return 1

    contract = parse_artifact(_read_json(run_dir / "contract.json"))
    if not isinstance(contract, RunContract):
        raise ValueError("contract.json is not a contract artifact")

    evidence_path = run_dir / "evidence.json"
    if evidence_path.exists():
        evidence = parse_artifact(_read_json(evidence_path))
        if not isinstance(evidence, EvidenceBundle):
            raise ValueError("evidence.json is not an evidence artifact")
    else:
        evidence = EvidenceBundle(verdict="pass")

    requirement_evidence: dict[str, tuple[str, ...]] = {}
    if evidence.verdict == "pass":
        requirement_evidence["proof"] = tuple(command.log_path for command in evidence.commands if command.exit_code == 0)
    audit = audit_completion(contract, evidence, requirement_evidence=requirement_evidence)
    _append_event(run_dir, {"event": "finished", "run_id": run_id, "status": audit.status})
    _print_json(
        {
            "run_id": run_id,
            "run_dir": str(run_dir),
            "status": audit.status,
            "proven": list(audit.proven),
            "unresolved": list(audit.unresolved),
        }
    )
    return 0 if audit.status == "pass" else 1


def _run_dir(root: Path, run_id: str) -> Path:
    return root / ".aidp" / "runs" / run_id


def _write_json(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f"{path.suffix}.tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def _read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def _append_event(run_dir: Path, payload: dict[str, object]) -> None:
    with (run_dir / "events.jsonl").open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")


def _print_json(payload: dict[str, object]) -> None:
    print(json.dumps(payload, sort_keys=True))


def _new_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _inject_default_start(argv: list[str] | None) -> list[str]:
    args = list(sys.argv[1:] if argv is None else argv)
    first_index = _first_positional_index(args)
    if first_index is not None and args[first_index] not in COMMANDS:
        args.insert(first_index, "start")
    return args


def _first_positional_index(args: list[str]) -> int | None:
    index = 0
    while index < len(args):
        token = args[index]
        if token in {"--version", "-h", "--help"}:
            return None
        if token == "--root":
            index += 2
            continue
        if token.startswith("--root="):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return index
    return None


if __name__ == "__main__":
    raise SystemExit(main())
