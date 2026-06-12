from aidp.adapters.codex import render_agents_md
from aidp.cli import main


def test_render_agents_md_is_compact_and_v2_first():
    content = render_agents_md()

    assert content.startswith("# AGENTS.md")
    assert 'aidp "<objective>"' in content
    assert "aidp check <run-id>" in content
    assert "aidp prove <run-id>" in content
    assert "aidp finish <run-id>" in content
    assert "Use subagents when independent review/research" in content
    assert "Read spans from `.aidp/runs/<run-id>/work.md`" in content
    assert ".claude" not in content
    assert "legacy" not in content.lower()
    assert len(content.splitlines()) <= 80


def test_adapter_codex_prints_agents_md(capsys):
    assert main(["adapter", "codex"]) == 0

    output = capsys.readouterr().out

    assert output.startswith("# AGENTS.md")
    assert 'aidp "<objective>"' in output


def test_adapter_codex_writes_without_overwriting(tmp_path, capsys):
    target = tmp_path / "AGENTS.md"

    assert main(["adapter", "codex", "--output", str(target)]) == 0
    payload = capsys.readouterr().out
    assert str(target) in payload
    assert target.read_text(encoding="utf-8").startswith("# AGENTS.md")

    assert main(["adapter", "codex", "--output", str(target)]) == 1
    error = capsys.readouterr().err
    assert "already exists" in error
