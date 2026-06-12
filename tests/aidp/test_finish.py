from aidp.finish import audit_completion
from aidp.models import CommandEvidence, EvidenceBundle, RunContract


def test_completion_audit_requires_direct_evidence_for_each_done_when():
    contract = RunContract(
        objective="ship v2",
        done_when=("unit", "review"),
        risk="low",
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
        review_results=("review",),
        verdict="pass",
    )

    audit = audit_completion(contract, evidence)

    assert audit.verdict == "pass"
    assert audit.proven == ("unit", "review")
    assert audit.unresolved == ()


def test_completion_audit_leaves_indirect_evidence_unresolved():
    contract = RunContract(
        objective="ship v2",
        done_when=("security",),
        risk="low",
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
        review_results=("looks good",),
        verdict="pass",
    )

    audit = audit_completion(contract, evidence)

    assert audit.verdict == "blocked"
    assert audit.proven == ()
    assert audit.unresolved == ("security",)
