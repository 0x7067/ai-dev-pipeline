"""Root conftest.py — adds repo root to sys.path for scripts.discover imports."""
import sys
import os

# Ensure the repo root is on sys.path so `from scripts.discover.*` works.
_repo_root = os.path.dirname(os.path.abspath(__file__))
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)
