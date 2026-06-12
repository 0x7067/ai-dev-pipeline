from __future__ import annotations

import re
import subprocess
from pathlib import Path

from aidp.models import CommandEvidence


def run_gate(
    *,
    label: str,
    command: tuple[str, ...],
    cwd: str | Path,
    log_dir: str | Path,
    timeout_seconds: int,
) -> CommandEvidence:
    cwd_path = Path(cwd)
    log_root = Path(log_dir)
    if not log_root.is_absolute():
        log_root = cwd_path / log_root
    log_root.mkdir(parents=True, exist_ok=True)

    log_path = log_root / f"{_safe_label(label)}.log"
    try:
        completed = subprocess.run(
            command,
            cwd=cwd_path,
            text=True,
            capture_output=True,
            timeout=timeout_seconds,
            check=False,
        )
        output = f"{completed.stdout}{completed.stderr}"
        exit_code = completed.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        output = f"{stdout}{stderr}\nTIMEOUT after {timeout_seconds}s\n"
        exit_code = 124

    log_path.write_text(output, encoding="utf-8")
    return CommandEvidence(
        label=label,
        command=command,
        exit_code=exit_code,
        log_path=_relative_log_path(log_path, cwd_path),
    )


def _safe_label(label: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9_.-]+", "-", label.strip()).strip("-")
    return safe or "gate"


def _relative_log_path(log_path: Path, cwd: Path) -> str:
    try:
        return str(log_path.relative_to(cwd))
    except ValueError:
        return str(log_path)
