import json

import pytest

from aidp.models import (
    CommandEvidence,
    ContextPack,
    ContextSource,
    EvidenceBundle,
    PlanTask,
    RunContract,
    WorkPlan,
    parse_artifact,
)


def test_run_contract_round_trips_required_fields():
    contract = RunContract(
        objective="replace the old pipeline",
        constraints=("no secrets", "ask before deletion"),
        done_when=("v2 doctor passes",),
        risk="medium",
        unsafe_actions=("delete old pipeline",),
        needs_question=True,
    )

    payload = contract.to_dict()
    restored = RunContract.from_dict(json.loads(json.dumps(payload)))

    assert restored == contract
    assert payload["schema_version"] == "aidp.contract.v1"
    assert payload["artifact"] == "contract"


def test_contract_rejects_empty_objective_and_unknown_risk():
    with pytest.raises(ValueError, match="objective"):
        RunContract(objective="", risk="low")

    with pytest.raises(ValueError, match="risk"):
        RunContract(objective="ship", risk="urgent")


def test_artifacts_reject_schema_version_mismatch():
    payload = RunContract(objective="ship", done_when=("proof",)).to_dict()
    payload["schema_version"] = "aidp.contract.v0"

    with pytest.raises(ValueError, match="schema_version"):
        RunContract.from_dict(payload)


def test_context_plan_and_evidence_parse_by_artifact_type():
    context = ContextPack(
        sources=(ContextSource(path="README.md", purpose="repo overview", spans=("1-20",)),),
        commands=("uv run pytest -q",),
        citations=("https://developers.openai.com/codex/learn/best-practices",),
        omitted=("large generated files",),
    )
    plan = WorkPlan(
        tasks=(
            PlanTask(
                title="typed artifacts",
                expected_paths=("aidp/models.py",),
                test_first=("tests/aidp/test_models.py",),
                proof_commands=("uv run pytest tests/aidp/test_models.py -q",),
            ),
        ),
        review_focus=("artifact validation",),
    )
    evidence = EvidenceBundle(
        commands=(
            CommandEvidence(
                label="unit",
                command=("uv", "run", "pytest", "tests/aidp", "-q"),
                exit_code=0,
                log_path=".aidp/runs/example/logs/unit.log",
            ),
        ),
        changed_files=("aidp/models.py",),
        review_results=("no blocking findings",),
        unresolved_risks=(),
        verdict="pass",
    )

    for artifact in (context, plan, evidence):
        restored = parse_artifact(artifact.to_dict())
        assert restored == artifact


def test_evidence_bundle_cannot_pass_with_unresolved_risks():
    with pytest.raises(ValueError, match="unresolved"):
        EvidenceBundle(
            commands=(),
            changed_files=("aidp/models.py",),
            review_results=(),
            unresolved_risks=("no review run",),
            verdict="pass",
        )
