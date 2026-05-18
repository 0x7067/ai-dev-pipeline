"""
core/features.py — pure feature extraction from Symbol/Match records.

Extracts structural features from parsed (trusted) records for clustering.
No I/O.

FC/IS layer: CORE (pure, no I/O)
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Sequence

# Import the trusted domain types defined in boundary
# (boundary is the parse layer; we only receive already-parsed objects here)


@dataclass(frozen=True)
class FileFeatures:
    """Structural features extracted from a single file's symbols."""

    filepath: str
    bucket: str
    symbol_count: int
    has_error_return: bool       # function/method returns error/Result/Either
    has_async_marker: bool       # async/await/Promise/Future/Task in symbol names or context
    dominant_kind: str           # most common canonical kind
    import_style: str            # "named" | "default" | "wildcard" | "none"
    return_type_style: str       # "explicit" | "inferred" | "void" | "unknown"


# ---------------------------------------------------------------------------
# Feature extraction helpers (pure)
# ---------------------------------------------------------------------------

_ERROR_NAMES = re.compile(
    r"\berr(or)?\b|\bException\b|\bResult\b|\bEither\b|\bFailure\b",
    re.IGNORECASE,
)
_ASYNC_NAMES = re.compile(
    r"\basync\b|\bawait\b|\bPromise\b|\bFuture\b|\bTask\b|\bCoroutine\b",
    re.IGNORECASE,
)


def _dominant_kind(kind_counts: dict[str, int]) -> str:
    if not kind_counts:
        return "unknown"
    return max(kind_counts, key=lambda k: kind_counts[k])


def extract_file_features(
    filepath: str,
    bucket: str,
    symbol_names: Sequence[str],
    symbol_kinds: Sequence[str],
    match_texts: Sequence[str],
) -> FileFeatures:
    """Derive FileFeatures from trusted symbol/match data for one file.

    All inputs are already-parsed domain values — no raw external data.
    """
    kind_counts: dict[str, int] = {}
    for k in symbol_kinds:
        kind_counts[k] = kind_counts.get(k, 0) + 1

    all_text = " ".join(list(symbol_names) + list(match_texts))

    has_error = bool(_ERROR_NAMES.search(all_text))
    has_async = bool(_ASYNC_NAMES.search(all_text))

    # Import style heuristic from match texts
    import_style = "none"
    combined = " ".join(match_texts)
    if re.search(r"\bimport\s+\*", combined):
        import_style = "wildcard"
    elif re.search(r"\bimport\s+\{", combined):
        import_style = "named"
    elif re.search(r"\bimport\b", combined):
        import_style = "default"

    # Return type style heuristic
    return_type_style = "unknown"
    if re.search(r"\s*->\s*\w", combined) or re.search(r":\s*\w+\s*\{", combined):
        return_type_style = "explicit"
    elif re.search(r"\breturn\b", combined):
        return_type_style = "inferred"
    elif re.search(r"\bvoid\b|\bNone\b|\bUnit\b", combined):
        return_type_style = "void"

    return FileFeatures(
        filepath=filepath,
        bucket=bucket,
        symbol_count=len(symbol_names),
        has_error_return=has_error,
        has_async_marker=has_async,
        dominant_kind=_dominant_kind(kind_counts),
        import_style=import_style,
        return_type_style=return_type_style,
    )
