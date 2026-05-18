"""
core/confidence.py — tri-band confidence scoring for /audit standards.

Converts raw frequency (0.0–1.0) to a ConfidenceBand and applies
threshold filtering. Pure, no I/O.

FC/IS layer: CORE (pure, no I/O)
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Sequence

from scripts.discover.core.cluster import Pattern


class ConfidenceBand(str, Enum):
    STRONG = "strong"    # frequency >= 0.80
    WEAK   = "weak"      # 0.60 <= frequency < 0.80
    NOISE  = "noise"     # frequency < 0.60  (suppressed)


@dataclass(frozen=True)
class ScoredPattern:
    pattern: Pattern
    band: ConfidenceBand
    confidence_pct: int   # round(frequency * 100)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

DEFAULT_THRESHOLD = 70  # percent


def score_pattern(pattern: Pattern) -> ScoredPattern:
    """Assign a ConfidenceBand to a Pattern."""
    pct = round(pattern.frequency * 100)
    if pattern.frequency >= 0.80:
        band = ConfidenceBand.STRONG
    elif pattern.frequency >= 0.60:
        band = ConfidenceBand.WEAK
    else:
        band = ConfidenceBand.NOISE
    return ScoredPattern(pattern=pattern, band=band, confidence_pct=pct)


def filter_by_threshold(
    scored: Sequence[ScoredPattern],
    threshold_pct: int = DEFAULT_THRESHOLD,
) -> list[ScoredPattern]:
    """Return only patterns at or above threshold_pct, in input order.

    The threshold partitions: >= threshold → surviving; < threshold → suppressed.
    NOISE patterns (< 60%) are always suppressed regardless of threshold.
    """
    return [
        sp for sp in scored
        if sp.confidence_pct >= threshold_pct and sp.band != ConfidenceBand.NOISE
    ]


def apply_threshold_bands(
    patterns: Sequence[Pattern],
    threshold_pct: int = DEFAULT_THRESHOLD,
) -> tuple[list[ScoredPattern], list[ScoredPattern]]:
    """Score all patterns and split into (surviving, suppressed).

    Returns (surviving, suppressed) where surviving are those at/above
    threshold_pct, suppressed are the rest.
    """
    scored = [score_pattern(p) for p in patterns]
    surviving = filter_by_threshold(scored, threshold_pct)
    suppressed = [sp for sp in scored if sp not in surviving]
    return surviving, suppressed
