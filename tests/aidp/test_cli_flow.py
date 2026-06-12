import json
import subprocess
import sys
from pathlib import Path

from aidp.cli import main
from aidp.models import EvidenceBundle, RunContract, WorkPlan, parse_artifact


def _json_stdout(capsys):
    captured = capsys.readouterr()
    return json.loads(captured.out)


def test_plan_writes_typed_run_artifacts(tmp_path, capsys):
    (tmp_path / "AGENTS.md").write_text("Verify with the smallest proof.\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("# Demo\n", encoding="utf-8")

    rc = main(
        [
            "--root",
            str(tmp_path),
            "plan",
            "replace the old pipeline",
            "--run-id",
            "run-001",
            "--proof-command",
            f"{sys.executable} -c \"print('ok')\"",
        ]
    )

    assert rc == 0
    payload = _json_stdout(capsys)
    run_dir = tmp_path / ".aidp" / "runs" / "run-001"
    assert payload == {"run_id": "run-001", "run_dir": str(run_dir), "status": "planned"}

    contract = parse_artifact(json.loads((run_dir / "contract.json").read_text(encoding="utf-8")))
    context = parse_artifact(json.loads((run_dir / "context.json").read_text(encoding="utf-8")))
    plan = parse_artifact(json.loads((run_dir / "plan.json").read_text(encoding="utf-8")))

    assert isinstance(contract, RunContract)
    assert contract.objective == "replace the old pipeline"
    assert contract.done_when == ("proof",)
    assert any(source.path == "AGENTS.md" for source in context.sources)
    assert isinstance(plan, WorkPlan)
    assert plan.tasks[0].proof_commands == (f"{sys.executable} -c \"print('ok')\"",)
    assert (run_dir / "events.jsonl").read_text(encoding="utf-8").count("\n") == 1


def test_prove_runs_plan_command_and_finish_passes(tmp_path, capsys):
    proof_command = f"{sys.executable} -c \"print('proof ok')\""
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "prove a vertical slice",
                "--run-id",
                "run-002",
                "--proof-command",
                proof_command,
            ]
        )
        == 0
    )
    capsys.readouterr()

    assert main(["--root", str(tmp_path), "prove", "run-002"]) == 0
    prove_payload = _json_stdout(capsys)
    run_dir = Path(prove_payload["run_dir"])
    evidence = parse_artifact(json.loads((run_dir / "evidence.json").read_text(encoding="utf-8")))

    assert isinstance(evidence, EvidenceBundle)
    assert evidence.verdict == "pass"
    assert evidence.commands[0].label == "proof"
    assert "proof ok" in (tmp_path / evidence.commands[0].log_path).read_text(encoding="utf-8")

    assert main(["--root", str(tmp_path), "finish", "run-002"]) == 0
    finish_payload = _json_stdout(capsys)
    assert finish_payload["status"] == "pass"
    assert finish_payload["proven"] == ["proof"]
    assert finish_payload["unresolved"] == []


def test_work_writes_compact_worker_brief_without_file_bodies(tmp_path, capsys):
    (tmp_path / "AGENTS.md").write_text("Smallest proof only.\n", encoding="utf-8")
    (tmp_path / "feature.py").write_text("SECRET_BODY_SHOULD_NOT_APPEAR = True\n", encoding="utf-8")
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "change feature behavior",
                "--run-id",
                "run-work",
                "--proof-command",
                f"{sys.executable} -c \"print('proof')\"",
            ]
        )
        == 0
    )
    capsys.readouterr()

    assert main(["--root", str(tmp_path), "work", "run-work"]) == 0
    payload = _json_stdout(capsys)
    run_dir = Path(payload["run_dir"])
    brief = (run_dir / "work.md").read_text(encoding="utf-8")

    assert payload["status"] == "ready"
    assert "brief_path" not in payload
    assert payload["work_packet"] == str(run_dir / "work.md")
    assert "Objective: change feature behavior" in brief
    assert "AGENTS.md" in brief
    assert "python" in brief
    assert "SECRET_BODY_SHOULD_NOT_APPEAR" not in brief
    assert "Run `aidp prove run-work` before `aidp finish run-work`" in brief


def test_finish_blocks_when_evidence_is_missing(tmp_path, capsys):
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "missing proof should block",
                "--run-id",
                "run-003",
            ]
        )
        == 0
    )
    capsys.readouterr()

    assert main(["--root", str(tmp_path), "finish", "run-003"]) == 1
    payload = _json_stdout(capsys)
    assert payload["status"] == "blocked"
    assert payload["unresolved"] == ["proof"]


def test_finish_fails_when_run_artifacts_are_invalid(tmp_path, capsys):
    proof_command = f"{sys.executable} -c \"print('proof ok')\""
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "reject invalid artifacts",
                "--run-id",
                "run-invalid",
                "--proof-command",
                proof_command,
            ]
        )
        == 0
    )
    capsys.readouterr()
    assert main(["--root", str(tmp_path), "prove", "run-invalid"]) == 0
    capsys.readouterr()

    plan_path = tmp_path / ".aidp" / "runs" / "run-invalid" / "plan.json"
    payload = json.loads(plan_path.read_text(encoding="utf-8"))
    payload["schema_version"] = "aidp.plan.v0"
    plan_path.write_text(json.dumps(payload), encoding="utf-8")

    assert main(["--root", str(tmp_path), "finish", "run-invalid"]) == 1
    finish_payload = _json_stdout(capsys)

    assert finish_payload["status"] == "fail"
    assert finish_payload["proven"] == []
    assert finish_payload["unresolved"] == [
        "plan.json: expected schema_version 'aidp.plan.v1', got 'aidp.plan.v0'"
    ]


def test_python_module_entrypoint_runs_doctor(tmp_path):
    result = subprocess.run(
        [sys.executable, "-m", "aidp", "--root", str(tmp_path), "doctor"],
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 0
    assert json.loads(result.stdout)["status"] == "ok"


def test_default_objective_creates_agentic_work_packet(tmp_path, capsys):
    (tmp_path / "AGENTS.md").write_text("Use rtk. Keep output short.\n", encoding="utf-8")
    (tmp_path / "README.md").write_text("# Demo\n", encoding="utf-8")

    rc = main(
        [
            "--root",
            str(tmp_path),
            "simplify the pipeline",
            "--run-id",
            "agent-001",
            "--proof-command",
            f"{sys.executable} -c \"print('agent proof')\"",
        ]
    )

    assert rc == 0
    payload = _json_stdout(capsys)
    run_dir = tmp_path / ".aidp" / "runs" / "agent-001"
    assert payload == {
        "run_id": "agent-001",
        "run_dir": str(run_dir),
        "status": "ready",
        "work_packet": str(run_dir / "work.md"),
    }

    packet = (run_dir / "work.md").read_text(encoding="utf-8")
    assert "# Agent Work Packet" in packet
    assert "Objective: simplify the pipeline" in packet
    assert "Read spans only; do not reread whole files." in packet
    assert "AGENTS.md:1-1" in packet
    assert f"{sys.executable} -c \"print('agent proof')\"" in packet
    assert len(packet.splitlines()) <= 80


def test_work_regenerates_compact_packet_from_artifacts(tmp_path, capsys):
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "make work packet",
                "--run-id",
                "agent-002",
                "--proof-command",
                f"{sys.executable} -c \"print('ok')\"",
            ]
        )
        == 0
    )
    capsys.readouterr()

    assert main(["--root", str(tmp_path), "work", "agent-002"]) == 0
    payload = _json_stdout(capsys)
    work_path = Path(payload["work_packet"])

    assert payload["status"] == "ready"
    assert work_path.name == "work.md"
    assert "make work packet" in work_path.read_text(encoding="utf-8")


def test_agent_prints_executable_prompt_from_work_packet(tmp_path, capsys):
    (tmp_path / "AGENTS.md").write_text("Keep context tight.\n", encoding="utf-8")
    (tmp_path / "feature.py").write_text("SECRET_BODY_SHOULD_NOT_APPEAR = True\n", encoding="utf-8")
    proof_command = f"{sys.executable} -c \"print('agent proof')\""
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "make the handoff executable",
                "--run-id",
                "agent-003",
                "--proof-command",
                proof_command,
            ]
        )
        == 0
    )
    capsys.readouterr()
    run_dir = tmp_path / ".aidp" / "runs" / "agent-003"
    (run_dir / "work.md").write_text("stale packet\n", encoding="utf-8")

    assert main(["--root", str(tmp_path), "agent", "agent-003"]) == 0
    prompt = capsys.readouterr().out

    assert (run_dir / "agent.md").read_text(encoding="utf-8") == prompt
    assert prompt.startswith("You are executing AIDP run agent-003.\n")
    assert "Read `.aidp/runs/agent-003/work.md` first." in prompt
    assert "Execute the work packet exactly." in prompt
    assert "## Work Packet" in prompt
    assert "stale packet" not in prompt
    assert "Objective: make the handoff executable" in prompt
    assert proof_command in prompt
    assert "aidp prove agent-003" in prompt
    assert "aidp finish agent-003" in prompt
    assert "SECRET_BODY_SHOULD_NOT_APPEAR" not in prompt
    assert len(prompt.splitlines()) <= 120
