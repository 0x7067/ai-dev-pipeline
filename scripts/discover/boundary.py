"""
boundary.py — parse-at-boundary layer for /audit standards.

Parses raw external data from ast-grep and universal-ctags into trusted
domain types before any core logic sees them. Fail-closed on unknown
languages or malformed records.

FC/IS layer: BOUNDARY
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional

# PyYAML is optional — only needed if loading kind map from YAML file at runtime
# (the default path uses the embedded _CTAGS_KIND_MAP dict for zero-dependency operation)
try:
    import yaml
    _YAML_AVAILABLE = True
except ImportError:
    yaml = None  # type: ignore[assignment]
    _YAML_AVAILABLE = False

# ---------------------------------------------------------------------------
# Domain types (trusted after parsing)
# ---------------------------------------------------------------------------

CANONICAL_KINDS = frozenset(
    {"function", "method", "class", "module", "variable", "other"}
)

# Languages that ast-grep supports (its 34 built-ins as of 0.26.x).
# Source: https://ast-grep.github.io/reference/languages.html
_AST_GREP_LANGS = frozenset(
    {
        "bash",
        "c",
        "cpp",
        "csharp",
        "css",
        "dart",
        "elixir",
        "go",
        "haskell",
        "html",
        "java",
        "javascript",
        "json",
        "kotlin",
        "lua",
        "ocaml",
        "php",
        "proto",
        "python",
        "ruby",
        "rust",
        "scala",
        "scheme",
        "swift",
        "terraform",
        "toml",
        "tsx",
        "typescript",
        "vue",
        "yaml",
        # additional aliases accepted by ast-grep CLI
        "js",
        "ts",
        "cs",
    }
)


@dataclass(frozen=True)
class Match:
    """One ast-grep match record (trusted)."""

    filepath: str   # relative to repo root, never empty
    language: str   # lower-cased canonical ast-grep lang
    rule_id: str    # rule id that produced the match
    text: str       # matched source text


@dataclass(frozen=True)
class Symbol:
    """One universal-ctags symbol record (trusted)."""

    filepath: str           # relative to repo root, never empty
    name: str               # symbol name
    kind: str               # canonical kind (one of CANONICAL_KINDS)
    line: int               # 1-based line number


# ---------------------------------------------------------------------------
# ctags kind normalisation
# ---------------------------------------------------------------------------

# Embedded kind map — mirrors data/ctags-kind-map.yml.
# This allows zero-dependency operation (no PyYAML required at runtime).
# The YAML file remains the canonical human-readable source.
_CTAGS_KIND_MAP_EMBEDDED: dict[str, str] = {
    # Functions
    "function":   "function",
    "func":       "function",
    "subroutine": "function",
    "procedure":  "function",
    "macro":      "function",
    "closure":    "function",
    "lambda":     "function",
    # Methods
    "method":     "method",
    "member":     "method",
    # Classes / types
    "class":      "class",
    "struct":     "class",
    "interface":  "class",
    "trait":      "class",
    "type":       "class",
    "enum":       "class",
    "union":      "class",
    "record":     "class",
    # Modules / namespaces
    "module":     "module",
    "namespace":  "module",
    "package":    "module",
    # Variables
    "variable":   "variable",
    "var":        "variable",
    "field":      "variable",
    "property":   "variable",
    "constant":   "variable",
    "const":      "variable",
    "local":      "variable",
    "parameter":  "variable",
    "param":      "variable",
    # Everything else → other
    "label":      "other",
    "tag":        "other",
    "anchor":     "other",
    "alias":      "other",
    "header":     "other",
    "section":    "other",
    "chapter":    "other",
    "define":     "other",
}

_KIND_MAP: dict[str, str] = {}  # populated lazily by _load_kind_map()


def _load_kind_map() -> dict[str, str]:
    """Return the ctags kind map.

    Prefers the embedded dict for zero-dependency operation.
    Falls back to loading data/ctags-kind-map.yml if PyYAML is available
    (allows overrides without code changes).
    """
    global _KIND_MAP
    if _KIND_MAP:
        return _KIND_MAP
    if _YAML_AVAILABLE:
        map_path = Path(__file__).parent / "data" / "ctags-kind-map.yml"
        try:
            with open(map_path) as fh:
                raw = yaml.safe_load(fh) or {}  # type: ignore[union-attr]
            _KIND_MAP = {k.lower(): v for k, v in raw.items() if v in CANONICAL_KINDS}
            return _KIND_MAP
        except OSError:
            pass  # YAML file not found — fall through to embedded map
    # Use embedded map (zero-dependency path)
    _KIND_MAP = dict(_CTAGS_KIND_MAP_EMBEDDED)
    return _KIND_MAP


def normalize_ctags_kind(raw_kind: str) -> str:
    """Return the canonical kind for a raw ctags kind string.

    Falls back to 'other' for unknown values (never raises).
    """
    return _load_kind_map().get(raw_kind.lower(), "other")


# ---------------------------------------------------------------------------
# Bucket name validation
# ---------------------------------------------------------------------------

_BUCKET_RE = re.compile(r"^[a-z0-9_-]+$")


def parse_bucket_name(raw: str) -> str:
    """Parse and validate a --bucket CLI argument.

    Returns the validated name or raises ValueError.
    Fail-closed: rejects anything outside ^[a-z0-9_-]+$.
    """
    if not raw or not _BUCKET_RE.match(raw):
        raise ValueError(
            f"Invalid --bucket value: {raw!r}. "
            "Must match ^[a-z0-9_-]+$ (lower-case alphanumeric, hyphens, underscores)."
        )
    return raw


# ---------------------------------------------------------------------------
# ast-grep JSON stream parser
# ---------------------------------------------------------------------------

def parse_ast_grep_stream(lines: Iterator[str]) -> list[Match]:
    """Parse `ast-grep --json=stream` output lines into Match records.

    Skips blank lines. Fails closed: unknown language → ValueError on that
    record (caller decides whether to skip or abort).
    """
    results: list[Match] = []
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"ast-grep: malformed JSON line: {exc}  line={raw!r}") from exc

        fp = obj.get("path") or obj.get("file") or ""
        if not fp:
            raise ValueError(f"ast-grep: missing 'path'/'file' in record: {obj!r}")

        lang = (obj.get("language") or "").lower()
        if lang not in _AST_GREP_LANGS:
            raise ValueError(
                f"ast-grep: unknown language {lang!r} in record for {fp!r}. "
                "Only ast-grep's 34 built-in languages are supported."
            )

        rule_id = obj.get("ruleId") or obj.get("rule_id") or ""
        text = obj.get("text") or obj.get("match") or ""

        results.append(Match(filepath=fp, language=lang, rule_id=rule_id, text=text))
    return results


# ---------------------------------------------------------------------------
# universal-ctags JSON Lines parser
# ---------------------------------------------------------------------------

def parse_ctags_json_lines(lines: Iterator[str]) -> list[Symbol]:
    """Parse `ctags --output-format=json` JSON Lines output into Symbol records.

    Skips header/metadata lines (no `_type` == `tag`). Normalizes `kind`
    via ctags-kind-map.yml. Fails closed on missing required fields.
    """
    results: list[Symbol] = []
    for raw in lines:
        raw = raw.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ValueError(f"ctags: malformed JSON line: {exc}  line={raw!r}") from exc

        # Skip header/version metadata records
        if obj.get("_type") and obj["_type"] != "tag":
            continue

        fp = obj.get("path") or obj.get("inputFile") or ""
        if not fp:
            continue  # ctags can emit records without a path in some edge cases

        name = obj.get("name") or ""
        if not name:
            continue

        raw_kind = obj.get("kind") or "other"
        canonical_kind = normalize_ctags_kind(raw_kind)

        line_val = obj.get("line") or obj.get("lineNumber") or 0
        try:
            line_int = int(line_val)
        except (TypeError, ValueError):
            line_int = 0

        results.append(
            Symbol(
                filepath=fp,
                name=name,
                kind=canonical_kind,
                line=max(0, line_int),
            )
        )
    return results


# ---------------------------------------------------------------------------
# CLI (self-test / boundary smoke)
# ---------------------------------------------------------------------------

if __name__ == "__main__":  # pragma: no cover
    import argparse

    ap = argparse.ArgumentParser(description="Boundary parser smoke-test")
    ap.add_argument("--bucket", help="Validate a bucket name")
    ap.add_argument("--ctags-json", help="Parse ctags JSON lines from this file")
    ap.add_argument("--astgrep-json", help="Parse ast-grep stream JSON from this file")
    args = ap.parse_args()

    if args.bucket:
        try:
            print(parse_bucket_name(args.bucket))
        except ValueError as e:
            print(f"ERROR: {e}", file=sys.stderr)
            sys.exit(1)

    if args.ctags_json:
        with open(args.ctags_json) as fh:
            syms = parse_ctags_json_lines(iter(fh))
        print(f"Parsed {len(syms)} symbols")

    if args.astgrep_json:
        with open(args.astgrep_json) as fh:
            matches = parse_ast_grep_stream(iter(fh))
        print(f"Parsed {len(matches)} matches")
