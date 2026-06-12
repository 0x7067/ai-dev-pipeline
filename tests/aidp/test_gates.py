import sys

from aidp.gates import run_gate


def test_run_gate_records_success_output_and_log(tmp_path):
    result = run_gate(
        label="unit",
        command=(sys.executable, "-c", "print('ok')"),
        cwd=tmp_path,
        log_dir=tmp_path / "logs",
        timeout_seconds=5,
    )

    assert result.label == "unit"
    assert result.exit_code == 0
    assert result.status == "pass"
    assert result.log_path.endswith("unit.log")
    assert (tmp_path / result.log_path).read_text(encoding="utf-8") == "ok\n"


def test_run_gate_records_nonzero_failure(tmp_path):
    result = run_gate(
        label="lint",
        command=(sys.executable, "-c", "import sys; print('bad'); sys.exit(7)"),
        cwd=tmp_path,
        log_dir=tmp_path / "logs",
        timeout_seconds=5,
    )

    assert result.exit_code == 7
    assert result.status == "fail"
    assert "lint.log" in result.log_path
    assert "bad" in (tmp_path / result.log_path).read_text(encoding="utf-8")
