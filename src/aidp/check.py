from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from aidp.models import ContextPack, EvidenceBundle, RunContract, WorkPlan, parse_artifact


@dataclass(frozen=True)
class CheckResult:
    status: str
    checked: tuple[str, ...]
    errors: tuple[str, ...]


REQUIRED_ARTIFACTS = ("contract.json", "context.json", "plan.json")
OPTIONAL_ARTIFACTS = ("evidence.json",)
EXPECTED_TYPES = {
    "contract.json": RunContract,
    "context.json": ContextPack,
    "plan.json": WorkPlan,
    "evidence.json": EvidenceBundle,
}


def check_run(root: str | Path, run_id: str) -> CheckResult:
    run_dir = Path(root) / ".aidp" / "runs" / run_id
    checked: list[str] = []
    errors: list[str] = []

    for name in (*REQUIRED_ARTIFACTS, *OPTIONAL_ARTIFACTS):
        path = run_dir / name
        if not path.exists():
            if name in REQUIRED_ARTIFACTS:
                errors.append(f"{name}: missing")
            continue
        try:
            artifact = parse_artifact(json.loads(path.read_text(encoding="utf-8")))
            expected_type = EXPECTED_TYPES[name]
            if not isinstance(artifact, expected_type):
                raise ValueError(f"expected artifact {expected_type.artifact!r}, got {artifact.artifact!r}")
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            errors.append(f"{name}: {exc}")
            continue
        checked.append(name)

    return CheckResult(
        status="pass" if not errors else "fail",
        checked=tuple(checked),
        errors=tuple(errors),
    )
