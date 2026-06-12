from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Surface:
    category: str
    path: str
    action: str


DELETE_SURFACES = (
    Surface("claude_commands", ".claude/commands", "delete"),
    Surface("claude_agents", ".claude/agents", "delete"),
    Surface("claude_skills", ".claude/skills", "delete"),
    Surface("claude_hooks", ".claude/hooks", "delete"),
    Surface("claude_rules", ".claude/rules", "delete"),
    Surface("claude_policy", ".claude/policy", "delete"),
    Surface("claude_settings", ".claude/settings.json", "delete"),
    Surface("claude_workflow_state", ".claude/workflow-state", "delete"),
    Surface("claude_workflow_state_file", ".claude/workflow-state.json", "delete"),
    Surface("retired_report_templates", "docs/templates", "delete"),
)

REVIEW_SURFACES = (
    Surface("github_workflows", ".github/workflows", "manual_review"),
    Surface("ci_templates", "templates/ci", "manual_review"),
    Surface("aidp_docs", "docs/aidp", "manual_review"),
    Surface("old_run_docs", "docs/runs", "manual_review"),
    Surface("retired_specs", "docs/specs", "manual_review"),
    Surface("retired_schemas", "docs/schemas", "manual_review"),
    Surface("retired_reference_docs", "docs/reference", "manual_review"),
    Surface("examples", "examples", "manual_review"),
    Surface("scripts", "scripts", "manual_review"),
    Surface("script_tests", "tests/scripts", "manual_review"),
    Surface("manifest_tests", "tests/manifest", "manual_review"),
    Surface("style_tests", "tests/style", "manual_review"),
    Surface("validator_tests", "tests/validator", "manual_review"),
)


def build_cutover_audit(root: str | Path) -> dict[str, Any]:
    project_root = Path(root)
    retired_surfaces: list[dict[str, Any]] = []
    delete_candidates: list[str] = []
    review_candidates: list[str] = []

    for surface in DELETE_SURFACES:
        report = _surface_report(project_root, surface)
        if report is None:
            continue
        retired_surfaces.append(report)
        delete_candidates.append(str(report["path"]))

    claude_plugin_report = _claude_plugin_report(project_root)
    if claude_plugin_report is not None:
        retired_surfaces.append(claude_plugin_report)
        delete_candidates.append(str(claude_plugin_report["path"]))

    for surface in REVIEW_SURFACES:
        report = _surface_report(project_root, surface)
        if report is None:
            continue
        retired_surfaces.append(report)
        review_candidates.append(str(report["path"]))

    needs_approval = bool(delete_candidates)
    return {
        "status": "needs_destructive_approval" if needs_approval else "ready",
        "destructive": False,
        "next_action": (
            "ask for explicit approval before deleting retired surfaces"
            if needs_approval
            else "no retired surfaces detected"
        ),
        "v2_readiness": _v2_readiness(project_root),
        "delete_candidates": delete_candidates,
        "review_candidates": review_candidates,
        "retired_surfaces": retired_surfaces,
    }


def _surface_report(root: Path, surface: Surface) -> dict[str, Any] | None:
    path = root / surface.path
    files = _files_under(path)
    if not files:
        return None
    return {
        "category": surface.category,
        "path": _display_path(path, root),
        "file_count": len(files),
        "action": surface.action,
    }


def _claude_plugin_report(root: Path) -> dict[str, Any] | None:
    plugin_dir = root / ".claude-plugin"
    files = _files_under(plugin_dir)
    if not files:
        return None

    manifest = plugin_dir / "plugin.json"
    if manifest.is_file():
        payload = _read_json_object(manifest)
        if payload is not None and _is_thin_v2_claude_plugin(payload):
            return None

    return {
        "category": "claude_plugin",
        "path": ".claude-plugin/",
        "file_count": len(files),
        "action": "delete",
    }


def _read_json_object(path: Path) -> dict[str, Any] | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def _is_thin_v2_claude_plugin(payload: dict[str, Any]) -> bool:
    return (
        payload.get("name") == "ai-dev-pipeline"
        and payload.get("skills") == "./skills/"
        and "commands" not in payload
        and "agents" not in payload
        and "hooks" not in payload
    )


def _files_under(path: Path) -> tuple[Path, ...]:
    if path.is_file():
        return (path,)
    if not path.is_dir():
        return ()
    return tuple(sorted(item for item in path.rglob("*") if item.is_file()))


def _display_path(path: Path, root: Path) -> str:
    relative = path.relative_to(root).as_posix()
    return f"{relative}/" if path.is_dir() else relative


def _v2_readiness(root: Path) -> dict[str, str]:
    readme = root / "README.md"
    agents = root / "AGENTS.md"
    readme_text = readme.read_text(encoding="utf-8", errors="replace") if readme.is_file() else ""
    agents_text = agents.read_text(encoding="utf-8", errors="replace") if agents.is_file() else ""
    return {
        "kernel": "present" if (root / "src" / "aidp" / "cli.py").is_file() else "missing",
        "agents": "v2-first" if agents_text.startswith("# AGENTS.md\n\n## AIDP v2") else "missing",
        "readme": "v2-first" if readme_text.startswith("# ai-dev-pipeline\n\nAIDP v2") else "missing",
        "schema_docs": "present" if _has_all_v2_schema_docs(root) else "missing",
        "schema_docs_git_visible": "present" if _gitignore_allows_docs_v2(root) else "ignored",
        "self_test": "present" if (root / "tests" / "aidp" / "test_selftest.py").is_file() else "missing",
    }


def _has_all_v2_schema_docs(root: Path) -> bool:
    return all(
        (root / "docs" / "v2" / f"{name}.schema.json").is_file()
        for name in ("contract", "context", "plan", "evidence")
    )


def _gitignore_allows_docs_v2(root: Path) -> bool:
    gitignore = root / ".gitignore"
    if not gitignore.is_file():
        return False
    lines = {
        line.strip()
        for line in gitignore.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    return "!docs/v2/" in lines and "!docs/v2/**" in lines
