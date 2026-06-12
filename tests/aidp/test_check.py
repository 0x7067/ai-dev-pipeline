import json
import sys
from pathlib import Path

from aidp.check import check_run
from aidp.cli import main


def test_check_run_accepts_valid_artifacts(tmp_path):
    assert (
        main(
            [
                "--root",
                str(tmp_path),
                "plan",
                "validate artifacts",
                "--run-id",
                "check-001",
                "--proof-command",
                f"{sys.executable} -c \"print('ok')\"",
            ]
        )
        == 0
    )

    result = check_run(tmp_path, "check-001")

    assert result.status == "pass"
    assert result.checked == ("contract.json", "context.json", "plan.json")
    assert result.errors == ()


def test_check_run_reports_malformed_artifact(tmp_path):
    assert main(["--root", str(tmp_path), "plan", "bad artifact", "--run-id", "check-002"]) == 0
    contract_path = tmp_path / ".aidp" / "runs" / "check-002" / "contract.json"
    payload = json.loads(contract_path.read_text(encoding="utf-8"))
    payload["risk"] = "urgent"
    contract_path.write_text(json.dumps(payload), encoding="utf-8")

    result = check_run(tmp_path, "check-002")

    assert result.status == "fail"
    assert result.checked == ("context.json", "plan.json")
    assert result.errors == ("contract.json: risk must be one of: low, medium, high",)


def test_check_run_rejects_wrong_artifact_kind_and_schema_version(tmp_path):
    assert main(["--root", str(tmp_path), "plan", "strict artifacts", "--run-id", "check-004"]) == 0
    run_dir = tmp_path / ".aidp" / "runs" / "check-004"

    contract_path = run_dir / "contract.json"
    contract_path.write_text(
        json.dumps(
            {
                "schema_version": "aidp.context.v1",
                "artifact": "context",
                "sources": [],
                "commands": [],
                "citations": [],
                "omitted": [],
            }
        ),
        encoding="utf-8",
    )

    plan_path = run_dir / "plan.json"
    plan_payload = json.loads(plan_path.read_text(encoding="utf-8"))
    plan_payload["schema_version"] = "aidp.plan.v0"
    plan_path.write_text(json.dumps(plan_payload), encoding="utf-8")

    result = check_run(tmp_path, "check-004")

    assert result.status == "fail"
    assert result.checked == ("context.json",)
    assert result.errors == (
        "contract.json: expected artifact 'contract', got 'context'",
        "plan.json: expected schema_version 'aidp.plan.v1', got 'aidp.plan.v0'",
    )


def test_check_cli_returns_json_status(tmp_path, capsys):
    assert main(["--root", str(tmp_path), "plan", "cli check", "--run-id", "check-003"]) == 0
    capsys.readouterr()

    assert main(["--root", str(tmp_path), "check", "check-003"]) == 0
    payload = json.loads(capsys.readouterr().out)

    assert payload == {
        "checked": ["contract.json", "context.json", "plan.json"],
        "errors": [],
        "run_id": "check-003",
        "status": "pass",
    }


def test_v2_schema_docs_exist():
    root = Path(__file__).resolve().parents[2]

    for name in ("contract", "context", "plan", "evidence"):
        schema_path = root / "docs" / "v2" / f"{name}.schema.json"
        payload = json.loads(schema_path.read_text(encoding="utf-8"))
        assert payload["$schema"] == "https://json-schema.org/draft/2020-12/schema"
        assert payload["title"].startswith("AIDP")
