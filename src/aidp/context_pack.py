from __future__ import annotations

from pathlib import Path
from typing import Iterable

from aidp.detect import detect_project
from aidp.models import ContextPack, ContextSource


PRIORITY_FILES = (
    "AGENTS.md",
    "README.md",
    "README",
    "pyproject.toml",
    "package.json",
    "Cargo.toml",
    "go.mod",
)


def _is_binary(path: Path) -> bool:
    try:
        chunk = path.read_bytes()[:1024]
    except OSError:
        return True
    return b"\x00" in chunk


def _line_span(path: Path) -> str:
    try:
        line_count = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
    except OSError:
        line_count = 1
    end = max(1, min(line_count, 80))
    return f"1-{end}"


def _purpose(path: Path, objective_terms: set[str]) -> str:
    name = path.name
    if name == "AGENTS.md":
        return "agent instructions"
    if name.startswith("README"):
        return "project overview"
    if name in {"pyproject.toml", "package.json", "Cargo.toml", "go.mod"}:
        return "toolchain detection"
    if objective_terms and any(term in path.as_posix().lower() for term in objective_terms):
        return "objective match"
    return "candidate context"


def _candidate_files(root: Path, objective: str) -> list[Path]:
    objective_terms = {term.lower() for term in objective.replace("-", " ").split() if len(term) >= 4}
    candidates: list[Path] = []

    for name in PRIORITY_FILES:
        path = root / name
        if path.is_file():
            candidates.append(path)

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel.startswith((".git/", ".venv/", "__pycache__/", ".pytest_cache/")):
            continue
        if path in candidates:
            continue
        if _is_binary(path):
            candidates.append(path)
            continue
        try:
            sample = path.read_text(encoding="utf-8", errors="replace").lower()
        except OSError:
            sample = ""
        haystack = f"{rel.lower()}\n{sample}"
        if objective_terms and not any(term in haystack for term in objective_terms):
            continue
        candidates.append(path)

    return candidates


def build_context_pack(
    root: str | Path,
    objective: str = "",
    paths: Iterable[str] | None = None,
    max_files: int = 40,
    max_spans: int = 220,
    max_file_bytes: int = 64_000,
    citations: tuple[str, ...] = (),
) -> ContextPack:
    project_root = Path(root)
    objective_terms = {term.lower() for term in objective.replace("-", " ").split() if len(term) >= 4}
    omitted: list[str] = []
    sources: list[ContextSource] = []
    span_count = 0
    candidates = [project_root / path for path in paths] if paths is not None else _candidate_files(project_root, objective)

    for path in candidates:
        rel = path.relative_to(project_root).as_posix()
        if _is_binary(path):
            omitted.append(f"binary: {rel}")
            continue
        try:
            size = path.stat().st_size
        except OSError:
            omitted.append(f"unreadable: {rel}")
            continue
        if size > max_file_bytes:
            omitted.append(f"large: {rel} ({size} bytes > {max_file_bytes})")
            continue
        if len(sources) >= max_files:
            omitted.append(f"file-cap: {rel}")
            continue
        if span_count >= max_spans:
            omitted.append(f"span-cap: {rel}")
            break
        sources.append(
            ContextSource(
                path=rel,
                purpose="selected context" if paths is not None else _purpose(path, objective_terms),
                spans=(_line_span(path),),
            )
        )
        span_count += 1

    profile = detect_project(project_root)
    commands = tuple(" ".join(command) for _, command in sorted(profile.commands.items()))

    return ContextPack(
        sources=tuple(sources),
        commands=commands,
        citations=citations,
        omitted=tuple(omitted),
    )
