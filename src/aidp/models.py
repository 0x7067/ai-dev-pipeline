from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, ClassVar


JsonDict = dict[str, Any]


def _as_tuple(value: Any, field_name: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if isinstance(value, str):
        raise ValueError(f"{field_name} must be a sequence, not a string")
    try:
        items = tuple(value)
    except TypeError as exc:
        raise ValueError(f"{field_name} must be a sequence") from exc
    for item in items:
        if not isinstance(item, str) or not item:
            raise ValueError(f"{field_name} entries must be non-empty strings")
    return items


def _require_text(value: Any, field_name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field_name} must be a non-empty string")
    return value


@dataclass(frozen=True)
class RunContract:
    schema_version: ClassVar[str] = "aidp.contract.v1"
    artifact: ClassVar[str] = "contract"

    objective: str
    constraints: tuple[str, ...] = field(default_factory=tuple)
    done_when: tuple[str, ...] = field(default_factory=tuple)
    risk: str = "low"
    unsafe_actions: tuple[str, ...] = field(default_factory=tuple)
    needs_question: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "objective", _require_text(self.objective, "objective"))
        if self.risk not in {"low", "medium", "high"}:
            raise ValueError("risk must be one of: low, medium, high")
        object.__setattr__(self, "constraints", _as_tuple(self.constraints, "constraints"))
        object.__setattr__(self, "done_when", _as_tuple(self.done_when, "done_when"))
        object.__setattr__(
            self,
            "unsafe_actions",
            _as_tuple(self.unsafe_actions, "unsafe_actions"),
        )

    def to_dict(self) -> JsonDict:
        return {
            "schema_version": self.schema_version,
            "artifact": self.artifact,
            "objective": self.objective,
            "constraints": list(self.constraints),
            "done_when": list(self.done_when),
            "risk": self.risk,
            "unsafe_actions": list(self.unsafe_actions),
            "needs_question": self.needs_question,
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> RunContract:
        _check_artifact(payload, cls.artifact, cls.schema_version)
        return cls(
            objective=payload.get("objective", ""),
            constraints=payload.get("constraints", ()),
            done_when=payload.get("done_when", ()),
            risk=payload.get("risk", "low"),
            unsafe_actions=payload.get("unsafe_actions", ()),
            needs_question=bool(payload.get("needs_question", False)),
        )


@dataclass(frozen=True)
class ContextSource:
    path: str
    purpose: str
    spans: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        object.__setattr__(self, "path", _require_text(self.path, "path"))
        object.__setattr__(self, "purpose", _require_text(self.purpose, "purpose"))
        object.__setattr__(self, "spans", _as_tuple(self.spans, "spans"))

    def to_dict(self) -> JsonDict:
        return {"path": self.path, "purpose": self.purpose, "spans": list(self.spans)}

    @classmethod
    def from_dict(cls, payload: JsonDict) -> ContextSource:
        return cls(
            path=payload.get("path", ""),
            purpose=payload.get("purpose", ""),
            spans=payload.get("spans", ()),
        )


@dataclass(frozen=True)
class ContextPack:
    schema_version: ClassVar[str] = "aidp.context.v1"
    artifact: ClassVar[str] = "context"

    sources: tuple[ContextSource, ...] = field(default_factory=tuple)
    commands: tuple[str, ...] = field(default_factory=tuple)
    citations: tuple[str, ...] = field(default_factory=tuple)
    omitted: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        object.__setattr__(self, "sources", tuple(self.sources))
        if not all(isinstance(source, ContextSource) for source in self.sources):
            raise ValueError("sources entries must be ContextSource")
        object.__setattr__(self, "commands", _as_tuple(self.commands, "commands"))
        object.__setattr__(self, "citations", _as_tuple(self.citations, "citations"))
        object.__setattr__(self, "omitted", _as_tuple(self.omitted, "omitted"))

    def to_dict(self) -> JsonDict:
        return {
            "schema_version": self.schema_version,
            "artifact": self.artifact,
            "sources": [source.to_dict() for source in self.sources],
            "commands": list(self.commands),
            "citations": list(self.citations),
            "omitted": list(self.omitted),
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> ContextPack:
        _check_artifact(payload, cls.artifact, cls.schema_version)
        return cls(
            sources=tuple(ContextSource.from_dict(item) for item in payload.get("sources", ())),
            commands=payload.get("commands", ()),
            citations=payload.get("citations", ()),
            omitted=payload.get("omitted", ()),
        )


@dataclass(frozen=True)
class PlanTask:
    title: str
    expected_paths: tuple[str, ...] = field(default_factory=tuple)
    test_first: tuple[str, ...] = field(default_factory=tuple)
    proof_commands: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        object.__setattr__(self, "title", _require_text(self.title, "title"))
        object.__setattr__(self, "expected_paths", _as_tuple(self.expected_paths, "expected_paths"))
        object.__setattr__(self, "test_first", _as_tuple(self.test_first, "test_first"))
        object.__setattr__(self, "proof_commands", _as_tuple(self.proof_commands, "proof_commands"))

    def to_dict(self) -> JsonDict:
        return {
            "title": self.title,
            "expected_paths": list(self.expected_paths),
            "test_first": list(self.test_first),
            "proof_commands": list(self.proof_commands),
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> PlanTask:
        return cls(
            title=payload.get("title", ""),
            expected_paths=payload.get("expected_paths", ()),
            test_first=payload.get("test_first", ()),
            proof_commands=payload.get("proof_commands", ()),
        )


@dataclass(frozen=True)
class WorkPlan:
    schema_version: ClassVar[str] = "aidp.plan.v1"
    artifact: ClassVar[str] = "plan"

    tasks: tuple[PlanTask, ...]
    review_focus: tuple[str, ...] = field(default_factory=tuple)

    def __post_init__(self) -> None:
        object.__setattr__(self, "tasks", tuple(self.tasks))
        if not self.tasks:
            raise ValueError("tasks must contain at least one task")
        if not all(isinstance(task, PlanTask) for task in self.tasks):
            raise ValueError("tasks entries must be PlanTask")
        object.__setattr__(self, "review_focus", _as_tuple(self.review_focus, "review_focus"))

    def to_dict(self) -> JsonDict:
        return {
            "schema_version": self.schema_version,
            "artifact": self.artifact,
            "tasks": [task.to_dict() for task in self.tasks],
            "review_focus": list(self.review_focus),
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> WorkPlan:
        _check_artifact(payload, cls.artifact, cls.schema_version)
        return cls(
            tasks=tuple(PlanTask.from_dict(item) for item in payload.get("tasks", ())),
            review_focus=payload.get("review_focus", ()),
        )


@dataclass(frozen=True)
class CommandEvidence:
    label: str
    command: tuple[str, ...]
    exit_code: int
    log_path: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "label", _require_text(self.label, "label"))
        object.__setattr__(self, "command", _as_tuple(self.command, "command"))
        if not isinstance(self.exit_code, int):
            raise ValueError("exit_code must be an integer")
        object.__setattr__(self, "log_path", _require_text(self.log_path, "log_path"))

    @property
    def status(self) -> str:
        return "pass" if self.exit_code == 0 else "fail"

    def to_dict(self) -> JsonDict:
        return {
            "label": self.label,
            "command": list(self.command),
            "exit_code": self.exit_code,
            "status": self.status,
            "log_path": self.log_path,
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> CommandEvidence:
        return cls(
            label=payload.get("label", ""),
            command=payload.get("command", ()),
            exit_code=payload.get("exit_code", -1),
            log_path=payload.get("log_path", ""),
        )


@dataclass(frozen=True)
class EvidenceBundle:
    schema_version: ClassVar[str] = "aidp.evidence.v1"
    artifact: ClassVar[str] = "evidence"

    commands: tuple[CommandEvidence, ...] = field(default_factory=tuple)
    changed_files: tuple[str, ...] = field(default_factory=tuple)
    review_results: tuple[str, ...] = field(default_factory=tuple)
    unresolved_risks: tuple[str, ...] = field(default_factory=tuple)
    verdict: str = "fail"

    def __post_init__(self) -> None:
        object.__setattr__(self, "commands", tuple(self.commands))
        if not all(isinstance(command, CommandEvidence) for command in self.commands):
            raise ValueError("commands entries must be CommandEvidence")
        object.__setattr__(self, "changed_files", _as_tuple(self.changed_files, "changed_files"))
        object.__setattr__(self, "review_results", _as_tuple(self.review_results, "review_results"))
        object.__setattr__(self, "unresolved_risks", _as_tuple(self.unresolved_risks, "unresolved_risks"))
        if self.verdict not in {"pass", "fail", "blocked"}:
            raise ValueError("verdict must be one of: pass, fail, blocked")
        if self.verdict == "pass" and self.unresolved_risks:
            raise ValueError("pass verdict cannot include unresolved risks")

    def to_dict(self) -> JsonDict:
        return {
            "schema_version": self.schema_version,
            "artifact": self.artifact,
            "commands": [command.to_dict() for command in self.commands],
            "changed_files": list(self.changed_files),
            "review_results": list(self.review_results),
            "unresolved_risks": list(self.unresolved_risks),
            "verdict": self.verdict,
        }

    @classmethod
    def from_dict(cls, payload: JsonDict) -> EvidenceBundle:
        _check_artifact(payload, cls.artifact, cls.schema_version)
        return cls(
            commands=tuple(CommandEvidence.from_dict(item) for item in payload.get("commands", ())),
            changed_files=payload.get("changed_files", ()),
            review_results=payload.get("review_results", ()),
            unresolved_risks=payload.get("unresolved_risks", ()),
            verdict=payload.get("verdict", "fail"),
        )


def parse_artifact(payload: JsonDict) -> RunContract | ContextPack | WorkPlan | EvidenceBundle:
    artifact = payload.get("artifact")
    parsers = {
        RunContract.artifact: RunContract.from_dict,
        ContextPack.artifact: ContextPack.from_dict,
        WorkPlan.artifact: WorkPlan.from_dict,
        EvidenceBundle.artifact: EvidenceBundle.from_dict,
    }
    try:
        return parsers[artifact](payload)
    except KeyError as exc:
        raise ValueError(f"unknown artifact type: {artifact!r}") from exc


def _check_artifact(payload: JsonDict, expected_artifact: str, expected_schema_version: str) -> None:
    actual_artifact = payload.get("artifact")
    if actual_artifact != expected_artifact:
        raise ValueError(f"expected artifact {expected_artifact!r}, got {actual_artifact!r}")
    actual_schema_version = payload.get("schema_version")
    if actual_schema_version != expected_schema_version:
        raise ValueError(f"expected schema_version {expected_schema_version!r}, got {actual_schema_version!r}")
