"""
core/cluster.py — pure pattern clustering for /audit standards.

Groups FileFeatures within a bucket into named patterns with frequency
counts and confidence scores. No I/O.

FC/IS layer: CORE (pure, no I/O)
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from scripts.discover.core.features import FileFeatures


@dataclass(frozen=True)
class Pattern:
    """A detected structural pattern within a bucket."""

    pattern_id: str        # <bucket>/<feature>/<value>
    bucket: str
    feature: str           # e.g. "import_style", "return_type_style"
    value: str             # e.g. "named", "explicit"
    count: int             # files exhibiting this value
    total: int             # files in bucket (denominator)
    frequency: float       # count / total  (0.0–1.0)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_id(bucket: str, feature: str, value: str) -> str:
    # Slugify: lower, replace space/slash with dash
    def slug(s: str) -> str:
        return s.lower().replace(" ", "-").replace("/", "-")
    return f"{slug(bucket)}/{slug(feature)}/{slug(value)}"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def cluster_bucket(
    bucket: str,
    features: Sequence[FileFeatures],
) -> list[Pattern]:
    """Cluster FileFeatures in a bucket into frequency-ranked Patterns.

    For each categorical feature dimension, count how many files have each
    value and compute frequency.  Returns list sorted by frequency descending,
    then pattern_id ascending (deterministic).

    Only features with more than one distinct value are interesting; single-
    value features (all files agree) are still returned so confidence scoring
    can award them maximum confidence.
    """
    if not features:
        return []

    total = len(features)

    # Feature dimensions to cluster on
    feature_accessors: dict[str, callable] = {
        "import_style": lambda f: f.import_style,
        "return_type_style": lambda f: f.return_type_style,
        "has_async_marker": lambda f: "async" if f.has_async_marker else "sync",
        "has_error_return": lambda f: "error-typed" if f.has_error_return else "no-error-type",
        "dominant_kind": lambda f: f.dominant_kind,
    }

    patterns: list[Pattern] = []
    for feat_name, accessor in feature_accessors.items():
        counts: dict[str, int] = {}
        for f in features:
            val = accessor(f)
            counts[val] = counts.get(val, 0) + 1

        for val, count in counts.items():
            freq = count / total
            patterns.append(
                Pattern(
                    pattern_id=_make_id(bucket, feat_name, val),
                    bucket=bucket,
                    feature=feat_name,
                    value=val,
                    count=count,
                    total=total,
                    frequency=freq,
                )
            )

    # Deterministic sort: frequency descending, then pattern_id ascending
    patterns.sort(key=lambda p: (-p.frequency, p.pattern_id))
    return patterns


def mode_frequency(patterns: list[Pattern], feature: str) -> float:
    """Return the highest frequency for a feature across patterns.

    Deterministic — max by frequency, ties broken by pattern_id ascending.
    Returns 0.0 if feature not present.
    """
    matching = [p for p in patterns if p.feature == feature]
    if not matching:
        return 0.0
    best = max(matching, key=lambda p: (p.frequency, p.pattern_id))
    return best.frequency
