import json

from aidp.cli import main


def test_self_test_proves_docs_and_code_scenarios(capsys):
    rc = main(["self-test"])

    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["status"] == "pass"
    assert [scenario["name"] for scenario in payload["scenarios"]] == ["docs-only", "code-test"]

    for scenario in payload["scenarios"]:
        assert scenario["pre_proof"] == "fail"
        assert scenario["change"] == "applied"
        assert scenario["check"] == "pass"
        assert scenario["prove"] == "pass"
        assert scenario["finish"] == "pass"
        assert scenario["work_packet"] == "present"
        assert scenario["agent_prompt"] == "present"
        assert scenario["bounded_context"] == "pass"

    assert payload["scenarios"][0]["changed_paths"] == ["README.md"]
    assert payload["scenarios"][1]["changed_paths"] == ["calc.py", "test_calc.py"]
