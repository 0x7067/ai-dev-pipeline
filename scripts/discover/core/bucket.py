"""
core/bucket.py — pure bucketing logic for /audit standards.

Assigns each file path to a named bucket based on glob-style path rules.
Unbucketed files are excluded from analysis.

FC/IS layer: CORE (pure, no I/O)
"""
from __future__ import annotations

import fnmatch
from dataclasses import dataclass
from typing import Optional, Sequence


# ---------------------------------------------------------------------------
# Bucket definitions (precedence order — first match wins)
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class BucketRule:
    name: str
    path_patterns: tuple[str, ...]   # fnmatch-style globs
    allowed_kinds: frozenset[str]    # canonical kinds from boundary.py; empty = all


# Precedence order per plan.
BUCKET_RULES: tuple[BucketRule, ...] = (
    BucketRule(
        name="tests",
        path_patterns=(
            "*/test/*",
            "*/tests/*",
            "*test/*",
            "*tests/*",
            "*.test.*",
            "*_test.*",
            "*.spec.*",
        ),
        allowed_kinds=frozenset(),  # all kinds
    ),
    BucketRule(
        name="http-handlers",
        path_patterns=(
            "*/api/*",
            "api/*",
            "*/handlers/*",
            "handlers/*",
            "*/routes/*",
            "routes/*",
            "*/controllers/*",
            "controllers/*",
        ),
        allowed_kinds=frozenset({"function", "method"}),
    ),
    BucketRule(
        name="background-jobs",
        path_patterns=(
            "*/jobs/*",
            "jobs/*",
            "*/workers/*",
            "workers/*",
            "*/tasks/*",
            "tasks/*",
        ),
        allowed_kinds=frozenset({"function", "method"}),
    ),
    BucketRule(
        name="cli-entrypoints",
        path_patterns=(
            "*/cli/*",
            "cli/*",
            "*/cmd/*",
            "cmd/*",
            "*/bin/*",
            "bin/*",
        ),
        allowed_kinds=frozenset({"function", "method"}),
    ),
    BucketRule(
        name="data-access",
        path_patterns=(
            "*/db/*",
            "db/*",
            "*/models/*",
            "models/*",
            "*/repository/*",
            "repository/*",
        ),
        allowed_kinds=frozenset({"class", "function"}),
    ),
    BucketRule(
        name="utilities",
        path_patterns=(
            "*/lib/*",
            "lib/*",
            "*/utils/*",
            "utils/*",
            "*/helpers/*",
            "helpers/*",
        ),
        allowed_kinds=frozenset({"function"}),
    ),
)

# Canonical bucket name set for validation
KNOWN_BUCKETS: frozenset[str] = frozenset(r.name for r in BUCKET_RULES)


# ---------------------------------------------------------------------------
# Path matching helpers
# ---------------------------------------------------------------------------

def _matches_any_pattern(path: str, patterns: tuple[str, ...]) -> bool:
    """Return True if `path` matches any of `patterns` (fnmatch, case-sensitive)."""
    for pat in patterns:
        if fnmatch.fnmatch(path, pat):
            return True
    return False


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def assign_bucket(filepath: str, kind: str) -> Optional[str]:
    """Assign a file+kind pair to a bucket name, or None if unbucketed.

    Precedence: first matching BucketRule wins.
    kind filtering: if BucketRule.allowed_kinds is non-empty, the kind must
    be in that set for the file to land in that bucket.

    Args:
        filepath: repo-relative path string
        kind:     canonical kind (function|method|class|module|variable|other)

    Returns:
        bucket name, or None
    """
    for rule in BUCKET_RULES:
        if _matches_any_pattern(filepath, rule.path_patterns):
            if rule.allowed_kinds and kind not in rule.allowed_kinds:
                # Path matches but kind is filtered out → keep searching
                continue
            return rule.name
    return None


def bucketize_paths(
    paths_with_kinds: Sequence[tuple[str, str]],
    target_bucket: Optional[str] = None,
) -> dict[str, list[str]]:
    """Group (filepath, kind) pairs into buckets.

    Args:
        paths_with_kinds: sequence of (filepath, kind) tuples
        target_bucket:    if set, only return entries for that bucket

    Returns:
        dict[bucket_name, list[filepath]]
    """
    result: dict[str, list[str]] = {}
    for filepath, kind in paths_with_kinds:
        bucket = assign_bucket(filepath, kind)
        if bucket is None:
            continue
        if target_bucket is not None and bucket != target_bucket:
            continue
        result.setdefault(bucket, []).append(filepath)
    return result
