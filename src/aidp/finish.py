from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Sequence

from aidp.models import EvidenceBundle, RunContract


@dataclass(frozen=True)
class CompletionAudit:
    status: str
    proven: tuple[str, ...]
    unresolved: tuple[str, ...]

    @property
    def verdict(self) -> str:
        return self.status


def _evidence_labels(evidence: EvidenceBundle) -> set[str]:
    labels = {command.label for command in evidence.commands if command.exit_code == 0}
    labels.update(evidence.review_results)
    return labels


def audit_completion(
    contract: RunContract,
    evidence: EvidenceBundle,
    requirement_evidence: Mapping[str, Sequence[str]] | None = None,
) -> CompletionAudit:
    explicit_evidence = requirement_evidence or {}
    direct_labels = _evidence_labels(evidence)
    proven: list[str] = []
    unresolved: list[str] = []

    for requirement in contract.done_when:
        refs = tuple(explicit_evidence.get(requirement, ()))
        if refs or requirement in direct_labels:
            proven.append(requirement)
        else:
            unresolved.append(requirement)

    if evidence.verdict != "pass":
        status = "fail"
    elif unresolved or evidence.unresolved_risks:
        status = "blocked"
    else:
        status = "pass"
    return CompletionAudit(
        status=status,
        proven=tuple(proven),
        unresolved=tuple(unresolved),
    )
