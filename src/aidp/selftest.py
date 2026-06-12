from __future__ import annotations

import io
import json
import sys
import tempfile
from collections.abc import Callable
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ScenarioResult:
    name: str
    run_id: str
    pre_proof: str
    change: str
    changed_paths: tuple[str, ...]
    check: str
    prove: str
    finish: str
    work_packet: str
    agent_prompt: str
    bounded_context: str
    errors: tuple[str, ...] = ()

    @property
    def status(self) -> str:
        if self.errors:
            return "fail"
        statuses = (
            self.pre_proof,
            self.change,
            self.check,
            self.prove,
            self.finish,
            self.work_packet,
            self.agent_prompt,
            self.bounded_context,
        )
        return (
            "pass"
            if statuses == ("fail", "applied", "pass", "pass", "pass", "present", "present", "pass")
            else "fail"
        )

    def to_dict(self) -> dict[str, object]:
        return {
            "name": self.name,
            "run_id": self.run_id,
            "pre_proof": self.pre_proof,
            "change": self.change,
            "changed_paths": list(self.changed_paths),
            "check": self.check,
            "prove": self.prove,
            "finish": self.finish,
            "work_packet": self.work_packet,
            "agent_prompt": self.agent_prompt,
            "bounded_context": self.bounded_context,
            "status": self.status,
            "errors": list(self.errors),
        }


def run_self_test() -> dict[str, object]:
    scenarios = (
        _run_docs_only_scenario(),
        _run_code_test_scenario(),
    )
    return {
        "status": "pass" if all(scenario.status == "pass" for scenario in scenarios) else "fail",
        "scenarios": [scenario.to_dict() for scenario in scenarios],
    }


def _run_docs_only_scenario() -> ScenarioResult:
    with tempfile.TemporaryDirectory(prefix="aidp-docs-only-") as temp_dir:
        root = Path(temp_dir)
        (root / "AGENTS.md").write_text("Verify with direct evidence.\n", encoding="utf-8")
        (root / "README.md").write_text("# Fixture\n\nDocs-only proof target pending.\n", encoding="utf-8")
        (root / "verify_docs.py").write_text(
            "from pathlib import Path\n\n"
            "assert 'V2_SELFTEST_DOCS_CHANGE' in Path('README.md').read_text(encoding='utf-8')\n"
            "print('docs proof')\n",
            encoding="utf-8",
        )
        proof = f"{sys.executable} verify_docs.py"
        return _run_scenario(
            root=root,
            name="docs-only",
            run_id="selftest-docs",
            objective="prove a docs-only change",
            proof_command=proof,
            forbidden_prompt_text="V2_SELFTEST_DOCS_CHANGE",
            apply_change=_apply_docs_only_change,
        )


def _run_code_test_scenario() -> ScenarioResult:
    with tempfile.TemporaryDirectory(prefix="aidp-code-test-") as temp_dir:
        root = Path(temp_dir)
        (root / "AGENTS.md").write_text("Use tests first for behavior changes.\n", encoding="utf-8")
        (root / "pyproject.toml").write_text("[project]\nname = \"fixture\"\nversion = \"0.0.0\"\n", encoding="utf-8")
        (root / "calc.py").write_text("def add(left, right):\n    return left + right\n", encoding="utf-8")
        (root / "verify_code.py").write_text(
            "from pathlib import Path\n"
            "import sys\n"
            "import unittest\n\n"
            "assert Path('test_calc.py').exists()\n"
            "suite = unittest.defaultTestLoader.discover('.', pattern='test_*.py')\n"
            "result = unittest.TextTestRunner(verbosity=0).run(suite)\n"
            "sys.exit(0 if result.wasSuccessful() else 1)\n",
            encoding="utf-8",
        )
        proof = f"{sys.executable} verify_code.py"
        return _run_scenario(
            root=root,
            name="code-test",
            run_id="selftest-code",
            objective="prove a code and test change",
            proof_command=proof,
            forbidden_prompt_text="return left + right",
            apply_change=_apply_code_test_change,
        )


def _run_scenario(
    *,
    root: Path,
    name: str,
    run_id: str,
    objective: str,
    proof_command: str,
    forbidden_prompt_text: str,
    apply_change: Callable[[Path], tuple[str, ...]],
) -> ScenarioResult:
    errors: list[str] = []
    start = _call_cli(["--root", str(root), objective, "--run-id", run_id, "--proof-command", proof_command])
    if start.return_code != 0:
        errors.append(f"start returned {start.return_code}")

    pre_proof = _call_cli(["--root", str(root), "prove", run_id])
    if _status_from_call(pre_proof) != "fail":
        errors.append("pre-proof did not fail before fixture change")

    changed_paths = apply_change(root)
    check = _call_cli(["--root", str(root), "check", run_id])
    prove = _call_cli(["--root", str(root), "prove", run_id])
    finish = _call_cli(["--root", str(root), "finish", run_id])
    agent = _call_cli(["--root", str(root), "agent", run_id])
    if agent.return_code != 0:
        errors.append(f"agent returned {agent.return_code}")

    run_dir = root / ".aidp" / "runs" / run_id
    work_path = run_dir / "work.md"
    agent_path = run_dir / "agent.md"
    prompt = agent_path.read_text(encoding="utf-8") if agent_path.exists() else ""
    bounded_context = "pass" if forbidden_prompt_text not in prompt else "fail"

    return ScenarioResult(
        name=name,
        run_id=run_id,
        pre_proof=_status_from_call(pre_proof),
        change="applied" if changed_paths else "missing",
        changed_paths=changed_paths,
        check=_status_from_call(check),
        prove=_status_from_call(prove),
        finish=_status_from_call(finish),
        work_packet="present" if work_path.exists() else "missing",
        agent_prompt="present" if agent_path.exists() else "missing",
        bounded_context=bounded_context,
        errors=tuple(errors),
    )


def _apply_docs_only_change(root: Path) -> tuple[str, ...]:
    readme = root / "README.md"
    readme.write_text(readme.read_text(encoding="utf-8") + "\nV2_SELFTEST_DOCS_CHANGE\n", encoding="utf-8")
    return ("README.md",)


def _apply_code_test_change(root: Path) -> tuple[str, ...]:
    (root / "calc.py").write_text(
        "def add(left, right):\n"
        "    return left + right\n\n\n"
        "def multiply(left, right):\n"
        "    return left * right\n",
        encoding="utf-8",
    )
    (root / "test_calc.py").write_text(
        "import unittest\n\n"
        "from calc import add, multiply\n\n\n"
        "class CalcTest(unittest.TestCase):\n"
        "    def test_adds_numbers(self):\n"
        "        self.assertEqual(add(2, 3), 5)\n\n"
        "    def test_multiplies_numbers(self):\n"
        "        self.assertEqual(multiply(2, 3), 6)\n\n\n"
        "if __name__ == '__main__':\n"
        "    unittest.main()\n",
        encoding="utf-8",
    )
    return ("calc.py", "test_calc.py")


@dataclass(frozen=True)
class _CliCall:
    return_code: int
    stdout: str
    payload: dict[str, Any]


def _call_cli(args: list[str]) -> _CliCall:
    from aidp.cli import main

    stdout = io.StringIO()
    stderr = io.StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        return_code = main(args)
    text = stdout.getvalue()
    payload = _json_payload(text)
    if return_code != 0 and stderr.getvalue():
        payload.setdefault("stderr", stderr.getvalue())
    return _CliCall(return_code=return_code, stdout=text, payload=payload)


def _json_payload(text: str) -> dict[str, Any]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _status_from_call(call: _CliCall) -> str:
    status = call.payload.get("status")
    if isinstance(status, str):
        return status
    return "pass" if call.return_code == 0 else "fail"
