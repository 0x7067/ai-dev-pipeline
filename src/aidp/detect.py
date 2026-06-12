from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping


CommandMap = Mapping[str, tuple[str, ...]]


@dataclass(frozen=True)
class ProjectProfile:
    root: Path
    languages: tuple[str, ...] = field(default_factory=tuple)
    package_manager: str | None = None
    commands: CommandMap = field(default_factory=dict)


def detect_project(root: str | Path) -> ProjectProfile:
    root_path = Path(root)
    languages: set[str] = set()
    commands: dict[str, tuple[str, ...]] = {}
    package_manager: str | None = None

    if (root_path / "pyproject.toml").exists():
        languages.add("python")
        package_manager = package_manager or "uv"
        commands.setdefault("test", ("uv", "run", "pytest", "-q"))
        commands.setdefault("doctor", ("python", "-m", "aidp", "doctor"))

    package_json = root_path / "package.json"
    if package_json.exists():
        languages.add("typescript")
        package_manager = _detect_js_package_manager(root_path, package_json)
        scripts = _read_package_scripts(package_json)
        if "test" in scripts:
            commands["test"] = (package_manager, "test")
        if "lint" in scripts:
            commands["lint"] = (package_manager, "lint")
        if "build" in scripts:
            commands["typecheck"] = (package_manager, "build")

    if (root_path / "Cargo.toml").exists():
        languages.add("rust")
        commands.setdefault("test", ("cargo", "test"))
        commands.setdefault("typecheck", ("cargo", "check"))

    if (root_path / "go.mod").exists():
        languages.add("go")
        commands.setdefault("go_test", ("go", "test", "./..."))
        commands.setdefault("go_build", ("go", "build", "./..."))

    return ProjectProfile(
        root=root_path,
        languages=tuple(sorted(languages)),
        package_manager=package_manager,
        commands=commands,
    )


def _detect_js_package_manager(root: Path, package_json: Path) -> str:
    data = _read_package_json(package_json)
    declared = data.get("packageManager", "")
    if isinstance(declared, str) and declared:
        return declared.split("@", 1)[0]
    if (root / "pnpm-lock.yaml").exists():
        return "pnpm"
    if (root / "yarn.lock").exists():
        return "yarn"
    if (root / "bun.lockb").exists() or (root / "bun.lock").exists():
        return "bun"
    return "npm"


def _read_package_scripts(package_json: Path) -> dict[str, str]:
    data = _read_package_json(package_json)
    scripts = data.get("scripts", {})
    if isinstance(scripts, dict):
        return {str(key): str(value) for key, value in scripts.items()}
    return {}


def _read_package_json(package_json: Path) -> dict[str, object]:
    try:
        data = json.loads(package_json.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    if isinstance(data, dict):
        return data
    return {}
