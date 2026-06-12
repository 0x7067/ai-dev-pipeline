from aidp.finish import audit_completion
from aidp.models import CommandEvidence, EvidenceBundle, RunContract


def test_completion_audit_passes_only_when_every_done_when_has_direct_evidence():
    contract = RunContract(
        objective="replace pipeline",
        done_when=("doctor passes", "unit tests pass"),
        risk="medium",
    )
    evidence = EvidenceBundle(
        commands=(
            CommandEvidence(
                label="unit tests",
                command=("uv", "run", "pytest", "tests/aidp", "-q"),
                exit_code=0,
                log_path=".aidp/runs/1/logs/unit.log",
            ),
        ),
        changed_files=("src/aidp/cli.py",),
        review_results=("reviewed completion audit",),
        verdict="pass",
    )

    audit = audit_completion(
        contract,
        evidence,
        requirement_evidence={
            "doctor passes": (".aidp/runs/1/logs/doctor.log",),
            "unit tests pass": (".aidp/runs/1/logs/unit.log",),
        },
    )

    assert audit.status == "pass"
    assert audit.unresolved == ()


def test_completion_audit_keeps_missing_evidence_unresolved():
    contract = RunContract(
        objective="replace pipeline",
        done_when=("doctor passes", "old pipeline deleted"),
        risk="high",
    )
    evidence = EvidenceBundle(
        commands=(),
        changed_files=("src/aidp/cli.py",),
        review_results=(),
        verdict="fail",
    )

    audit = audit_completion(
        contract,
        evidence,
        requirement_evidence={"doctor passes": (".aidp/runs/1/logs/doctor.log",)},
    )

    assert audit.status == "fail"
    assert audit.unresolved == ("old pipeline deleted",)
