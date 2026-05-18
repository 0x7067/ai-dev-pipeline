"""
core/report.py — pure report generation for /audit standards.

Builds the markdown content for .claude/discovered-patterns/<id>.md files.
No file I/O — returns strings for the shell layer to write.

FC/IS layer: CORE (pure, no I/O)
"""
from __future__ import annotations

from datetime import datetime
from typing import Sequence

from scripts.discover.core.confidence import ScoredPattern


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def render_pattern_doc(
    sp: ScoredPattern,
    template: str,
    scanned_at: datetime,
) -> str:
    """Render a discovered-pattern markdown doc from the template.

    Substitutes template placeholders with actual values.
    Returns the rendered string (not written to disk here).
    """
    p = sp.pattern
    return (
        template
        .replace("{{pattern_id}}", p.pattern_id)
        .replace("{{bucket}}", p.bucket)
        .replace("{{feature}}", p.feature)
        .replace("{{value}}", p.value)
        .replace("{{count}}", str(p.count))
        .replace("{{total}}", str(p.total))
        .replace("{{confidence_pct}}", str(sp.confidence_pct))
        .replace("{{band}}", sp.band.value)
        .replace("{{frequency_pct}}", f"{p.frequency * 100:.1f}")
        .replace("{{scanned_at}}", scanned_at.strftime("%Y-%m-%dT%H:%M:%SZ"))
    )


def build_gc_set(surviving: Sequence[ScoredPattern]) -> frozenset[str]:
    """Return the set of pattern_ids that should exist after this scan.

    The shell layer deletes any .claude/discovered-patterns/<id>.md files
    whose id is NOT in this set.
    """
    return frozenset(sp.pattern.pattern_id for sp in surviving)


def pattern_id_to_filename(pattern_id: str) -> str:
    """Convert a pattern_id to a safe filename.

    Replaces '/' with '__' so it can be a flat filename.
    e.g. "utilities/import_style/named" → "utilities__import_style__named.md"
    """
    return pattern_id.replace("/", "__") + ".md"
