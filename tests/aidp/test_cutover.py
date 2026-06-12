import json

from aidp.cli import main
from aidp.cutover import build_cutover_audit


def _write(path, text="x\n"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_cutover_audit_reports_retired_surfaces_without_deleting(tmp_path):
    _write(tmp_path / ".claude" / "commands" / "ship.md")
    _write(tmp_path / ".claude" / "agents" / "planner.md")
    _write(tmp_path / ".claude" / "skills" / "using-pipeline" / "SKILL.md")
    _write(tmp_path / ".claude" / "hooks" / "workflow-gate.sh")
    _write(tmp_path / ".claude" / "rules" / "release-and-verification.md")
    _write(tmp_path / ".claude" / "policy" / "approvals.yaml")
    _write(tmp_path / ".claude" / "settings.json")
    _write(tmp_path / ".claude-plugin" / "plugin.json")
    _write(tmp_path / "docs" / "templates" / "current-plan-template.md")
    _write(tmp_path / "docs" / "templates" / "verify-report-template.md")
    _write(tmp_path / "docs" / "specs" / "old" / "spec.md")
    _write(tmp_path / "examples" / "python" / "fcis_layers.py")
    _write(tmp_path / "scripts" / "run-verification-gates.sh")
    _write(tmp_path / "tests" / "scripts" / "test-plan-gate.sh")
    _write(tmp_path / "src" / "aidp" / "cli.py")
    _write(tmp_path / "tests" / "aidp" / "test_selftest.py")
    for name in ("contract", "context", "plan", "evidence"):
        _write(tmp_path / "docs" / "v2" / f"{name}.schema.json")
    _write(tmp_path / ".gitignore", "docs/*\n!docs/v2/\n!docs/v2/**\n")
    _write(tmp_path / "README.md", "# ai-dev-pipeline\n\nAIDP v2 replacement.\n")
    _write(tmp_path / "AGENTS.md", "# AGENTS.md\n\n## AIDP v2\n")

    audit = build_cutover_audit(tmp_path)

    assert audit["status"] == "needs_destructive_approval"
    assert audit["destructive"] is False
    assert audit["next_action"] == "ask for explicit approval before deleting retired surfaces"
    assert audit["v2_readiness"] == {
        "kernel": "present",
        "agents": "v2-first",
        "readme": "v2-first",
        "schema_docs": "present",
        "schema_docs_git_visible": "present",
        "self_test": "present",
    }
    assert audit["delete_candidates"] == [
        ".claude/commands/",
        ".claude/agents/",
        ".claude/skills/",
        ".claude/hooks/",
        ".claude/rules/",
        ".claude/policy/",
        ".claude/settings.json",
        "docs/templates/",
        ".claude-plugin/",
    ]
    assert audit["review_candidates"] == [
        "docs/specs/",
        "examples/",
        "scripts/",
        "tests/scripts/",
    ]
    assert {surface["category"] for surface in audit["retired_surfaces"]} == {
        "claude_agents",
        "claude_commands",
        "claude_hooks",
        "claude_policy",
        "claude_rules",
        "claude_settings",
        "claude_skills",
        "claude_plugin",
        "retired_report_templates",
        "retired_specs",
        "examples",
        "scripts",
        "script_tests",
    }
    assert (tmp_path / ".claude" / "commands" / "ship.md").exists()
    assert (tmp_path / "docs" / "templates" / "verify-report-template.md").exists()


def test_cutover_cli_prints_json_audit(tmp_path, capsys):
    _write(tmp_path / ".claude" / "commands" / "ship.md")
    _write(tmp_path / "src" / "aidp" / "cli.py")
    _write(tmp_path / "tests" / "aidp" / "test_selftest.py")
    for name in ("contract", "context", "plan", "evidence"):
        _write(tmp_path / "docs" / "v2" / f"{name}.schema.json")
    _write(tmp_path / "README.md", "# ai-dev-pipeline\n\nAIDP v2 replacement.\n")
    _write(tmp_path / "AGENTS.md", "# AGENTS.md\n\n## AIDP v2\n")

    rc = main(["--root", str(tmp_path), "cutover"])

    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["status"] == "needs_destructive_approval"
    assert payload["delete_candidates"] == [".claude/commands/"]
    assert payload["retired_surfaces"][0]["file_count"] == 1


def test_cutover_accepts_thin_v2_claude_plugin_manifest(tmp_path):
    _write(tmp_path / "src" / "aidp" / "cli.py")
    _write(tmp_path / "tests" / "aidp" / "test_selftest.py")
    for name in ("contract", "context", "plan", "evidence"):
        _write(tmp_path / "docs" / "v2" / f"{name}.schema.json")
    _write(tmp_path / ".gitignore", "docs/*\n!docs/v2/\n!docs/v2/**\n")
    _write(tmp_path / "README.md", "# ai-dev-pipeline\n\nAIDP v2 package.\n")
    _write(tmp_path / "AGENTS.md", "# AGENTS.md\n\n## AIDP v2\n")
    _write(
        tmp_path / ".claude-plugin" / "plugin.json",
        '{\n'
        '  "name": "ai-dev-pipeline",\n'
        '  "skills": "./skills/",\n'
        '  "version": "0.1.0"\n'
        '}\n',
    )

    audit = build_cutover_audit(tmp_path)

    assert audit["status"] == "ready"
    assert audit["delete_candidates"] == []
    assert audit["retired_surfaces"] == []
