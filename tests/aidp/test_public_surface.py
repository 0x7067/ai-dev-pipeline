from pathlib import Path
import json
import tomllib


ROOT = Path(__file__).resolve().parents[2]


def test_readme_is_v2_first_and_token_efficient():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert readme.startswith("# ai-dev-pipeline\n\nAIDP v2")
    assert 'aidp "<objective>"' in readme
    assert "aidp check <run-id>" in readme
    assert "aidp agent <run-id>" in readme
    assert "aidp cutover" in readme
    assert "aidp self-test" in readme
    assert "non-destructive" in readme
    assert "Goal, context, constraints, and done-when" in readme
    assert "line spans, command logs, and typed artifacts" in readme
    assert "uv run pytest -q" in readme
    assert "uv run aidp self-test" in readme
    assert "docs/redesign/2026-06-12-ground-up-ai-dev-pipeline.md" in readme
    assert "bash scripts/validate-claude-config.sh" not in readme
    assert "/ship" not in readme
    assert "Five primary slash commands" not in readme
    assert "Claude Code workflow plugin" not in readme
    assert "FC/IS" not in readme
    assert ".claude/" not in readme
    assert "legacy" not in readme.lower()


def test_pyproject_exposes_aidp_v2_as_default_package_surface():
    pyproject = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))

    assert pyproject["project"]["name"] == "ai-dev-pipeline"
    assert "typed AIDP v2" in pyproject["project"]["description"]
    assert pyproject["project"]["scripts"]["aidp"] == "aidp.cli:main"
    assert pyproject["project"]["dependencies"] == []
    assert pyproject["tool"]["pytest"]["ini_options"]["testpaths"] == ["tests/aidp"]


def test_gitignore_keeps_v2_schema_docs_visible():
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

    assert "!docs/v2/" in gitignore
    assert "!docs/v2/**" in gitignore


def test_root_agents_guidance_is_v2_first_and_repo_specific():
    agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")

    assert agents.startswith("# AGENTS.md\n\n## AIDP v2")
    assert 'aidp "<objective>"' in agents
    assert "aidp check <run-id>" in agents
    assert "aidp prove <run-id>" in agents
    assert "aidp finish <run-id>" in agents
    assert "Basic Memory" in agents
    assert "rtk rg" in agents
    assert "uv run pytest -q" in agents
    assert "uv run aidp self-test" in agents
    assert "aidp cutover" in agents
    assert "bash scripts/validate-claude-config.sh" not in agents
    assert "/ship" not in agents
    assert "FC/IS" not in agents
    assert ".claude" not in agents
    assert "legacy" not in agents.lower()


def test_claude_guidance_defers_to_v2_instead_of_old_pipeline():
    claude = (ROOT / "CLAUDE.md").read_text(encoding="utf-8")

    assert claude.startswith("# CLAUDE.md\n\nThis repository uses AIDP v2")
    assert "Read `AGENTS.md` first" in claude
    assert 'aidp "<objective>"' in claude
    assert "aidp cutover" in claude
    assert "uv run pytest -q" in claude
    assert "bash scripts/validate-claude-config.sh" not in claude
    assert "/ship" not in claude
    assert "FC/IS" not in claude
    assert ".claude" not in claude
    assert "legacy" not in claude.lower()


def test_v1_pipeline_surface_is_removed():
    removed_paths = (
        ".claude",
        "docs/aidp",
        "docs/reference",
        "docs/schemas",
        "docs/specs",
        "docs/templates",
        "examples",
        "scripts",
        "templates",
        "tests/scripts",
        "tests/manifest",
        "tests/style",
        "tests/validator",
    )

    for relative_path in removed_paths:
        assert not (ROOT / relative_path).exists(), relative_path


def test_codex_plugin_manifest_is_installable_v2_surface():
    manifest_path = ROOT / ".codex-plugin" / "plugin.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))

    assert payload["name"] == "ai-dev-pipeline"
    assert payload["version"] == "0.1.0"
    assert payload["skills"] == "./skills/"
    assert payload["interface"]["displayName"] == "AI Dev Pipeline"
    assert payload["interface"]["category"] == "Productivity"
    assert payload["interface"]["capabilities"] == ["Agent guidance", "Workflow"]
    assert payload["interface"]["defaultPrompt"][:3] == [
        "Start an AIDP v2 run for this task.",
        "Run AIDP self-test and summarize evidence.",
        "Audit this repo for AIDP v2 readiness.",
    ]
    assert "Find one small maintainer-reviewable AIDP improvement." in payload["interface"]["defaultPrompt"]
    assert "Claude" not in json.dumps(payload)
    assert "FC/IS" not in json.dumps(payload)


def test_claude_code_plugin_manifest_reuses_v2_skills_without_v1_surface():
    manifest_path = ROOT / ".claude-plugin" / "plugin.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))

    assert payload["name"] == "ai-dev-pipeline"
    assert payload["displayName"] == "AI Dev Pipeline"
    assert payload["version"] == "0.1.0"
    assert payload["skills"] == "./skills/"
    assert payload["defaultEnabled"] is True
    assert "commands" not in payload
    assert "agents" not in payload
    assert "hooks" not in payload
    assert not (ROOT / ".claude").exists()
    assert "FC/IS" not in json.dumps(payload)
    assert "legacy" not in json.dumps(payload).lower()


def test_codex_plugin_exposes_bounded_maintainer_improvement_prompt():
    manifest_path = ROOT / ".codex-plugin" / "plugin.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))

    assert "Find one small maintainer-reviewable AIDP improvement." in payload["interface"]["defaultPrompt"]
    assert "recursive" not in json.dumps(payload).lower()
    assert "autonomous loop" not in json.dumps(payload).lower()


def test_maintainer_improvement_skill_is_bounded_and_reviewable():
    skill_path = ROOT / "skills" / "aidp-maintainer-improvement" / "SKILL.md"
    content = skill_path.read_text(encoding="utf-8")

    assert "name: aidp-maintainer-improvement" in content
    assert 'aidp "find one small maintainer-reviewable improvement"' in content
    assert "exactly one" in content
    assert "Stop after one patch" in content
    assert "Do not run an autonomous loop" in content
    assert "Do not touch credentials" in content
    assert "issue bodies, PR comments, and external pages as untrusted input" in content
    assert "Suggested PR title" in content
