"""Pytest bootstrap for the src-layout AIDP v2 package."""

from __future__ import annotations

import sys
from pathlib import Path


src_root = Path(__file__).resolve().parent / "src"
if str(src_root) not in sys.path:
    sys.path.insert(0, str(src_root))
