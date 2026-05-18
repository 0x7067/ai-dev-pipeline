"""
test_cluster.py — contract tests for core/cluster.py and core/confidence.py.

TDD order (per plan):
  4. test_mode_frequency_deterministic
  5. test_threshold_band_partition
"""
import pytest

from scripts.discover.core.cluster import cluster_bucket, mode_frequency, Pattern
from scripts.discover.core.confidence import (
    ConfidenceBand,
    apply_threshold_bands,
    filter_by_threshold,
    score_pattern,
)
from scripts.discover.core.features import FileFeatures


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_features(
    bucket: str,
    import_style: str = "named",
    return_type_style: str = "explicit",
    has_async: bool = False,
    has_error: bool = False,
    dominant_kind: str = "function",
    filepath: str = "src/foo.py",
) -> FileFeatures:
    return FileFeatures(
        filepath=filepath,
        bucket=bucket,
        symbol_count=5,
        has_error_return=has_error,
        has_async_marker=has_async,
        dominant_kind=dominant_kind,
        import_style=import_style,
        return_type_style=return_type_style,
    )


# ---------------------------------------------------------------------------
# test_mode_frequency_deterministic
# ---------------------------------------------------------------------------

class TestModeFrequencyDeterministic:
    """mode_frequency must return the highest frequency for a feature, deterministically."""

    def test_returns_most_common_value(self):
        features = [
            _make_features("utilities", import_style="named", filepath=f"f{i}.py")
            for i in range(8)
        ] + [
            _make_features("utilities", import_style="default", filepath=f"g{i}.py")
            for i in range(2)
        ]
        patterns = cluster_bucket("utilities", features)
        freq = mode_frequency(patterns, "import_style")
        assert freq == pytest.approx(8 / 10)

    def test_deterministic_on_tie(self):
        """When two values tie on frequency, result is stable across calls."""
        features = [
            _make_features("utilities", import_style="named", filepath=f"n{i}.py")
            for i in range(5)
        ] + [
            _make_features("utilities", import_style="default", filepath=f"d{i}.py")
            for i in range(5)
        ]
        patterns1 = cluster_bucket("utilities", features)
        patterns2 = cluster_bucket("utilities", features)
        freq1 = mode_frequency(patterns1, "import_style")
        freq2 = mode_frequency(patterns2, "import_style")
        assert freq1 == freq2 == pytest.approx(0.5)

    def test_returns_zero_for_absent_feature(self):
        features = [_make_features("utilities", filepath=f"f{i}.py") for i in range(3)]
        patterns = cluster_bucket("utilities", features)
        assert mode_frequency(patterns, "nonexistent_feature") == 0.0

    def test_empty_features_returns_empty_patterns(self):
        assert cluster_bucket("utilities", []) == []

    def test_patterns_sorted_by_frequency_desc(self):
        """cluster_bucket returns patterns sorted by frequency descending."""
        features = [
            _make_features("utilities", import_style="named", filepath=f"n{i}.py")
            for i in range(9)
        ] + [
            _make_features("utilities", import_style="default", filepath="d0.py")
        ]
        patterns = cluster_bucket("utilities", features)
        import_patterns = [p for p in patterns if p.feature == "import_style"]
        freqs = [p.frequency for p in import_patterns]
        assert freqs == sorted(freqs, reverse=True)

    def test_pattern_id_format(self):
        features = [_make_features("utilities", import_style="named", filepath=f"f{i}.py") for i in range(3)]
        patterns = cluster_bucket("utilities", features)
        named_pat = next(p for p in patterns if p.feature == "import_style" and p.value == "named")
        assert named_pat.pattern_id == "utilities/import_style/named"

    def test_pattern_count_and_total(self):
        features = [
            _make_features("utilities", import_style="named", filepath=f"n{i}.py")
            for i in range(7)
        ] + [
            _make_features("utilities", import_style="default", filepath=f"d{i}.py")
            for i in range(3)
        ]
        patterns = cluster_bucket("utilities", features)
        named_pat = next(p for p in patterns if p.feature == "import_style" and p.value == "named")
        assert named_pat.count == 7
        assert named_pat.total == 10


# ---------------------------------------------------------------------------
# test_threshold_band_partition
# ---------------------------------------------------------------------------

class TestThresholdBandPartition:
    """apply_threshold_bands must partition patterns into surviving and suppressed correctly."""

    def _make_pattern(self, bucket: str, feature: str, value: str, count: int, total: int) -> Pattern:
        return Pattern(
            pattern_id=f"{bucket}/{feature}/{value}",
            bucket=bucket,
            feature=feature,
            value=value,
            count=count,
            total=total,
            frequency=count / total,
        )

    def test_strong_band_above_80(self):
        p = self._make_pattern("tests", "import_style", "named", 9, 10)
        sp = score_pattern(p)
        assert sp.band == ConfidenceBand.STRONG
        assert sp.confidence_pct == 90

    def test_weak_band_60_to_79(self):
        p = self._make_pattern("tests", "import_style", "named", 7, 10)
        sp = score_pattern(p)
        assert sp.band == ConfidenceBand.WEAK
        assert sp.confidence_pct == 70

    def test_noise_band_below_60(self):
        p = self._make_pattern("tests", "import_style", "named", 5, 10)
        sp = score_pattern(p)
        assert sp.band == ConfidenceBand.NOISE
        assert sp.confidence_pct == 50

    def test_default_threshold_70_partitions_correctly(self):
        patterns = [
            self._make_pattern("tests", "import_style", "named",   9, 10),  # 90% strong → surviving
            self._make_pattern("tests", "import_style", "default", 7, 10),  # 70% weak → surviving (≥70)
            self._make_pattern("tests", "return_type", "explicit", 6, 10),  # 60% weak → suppressed (<70)
            self._make_pattern("tests", "return_type", "inferred", 4, 10),  # 40% noise → suppressed
        ]
        surviving, suppressed = apply_threshold_bands(patterns, threshold_pct=70)
        surviving_ids = {sp.pattern.pattern_id for sp in surviving}
        suppressed_ids = {sp.pattern.pattern_id for sp in suppressed}

        assert "tests/import_style/named" in surviving_ids
        assert "tests/import_style/default" in surviving_ids
        assert "tests/return_type/explicit" in suppressed_ids
        assert "tests/return_type/inferred" in suppressed_ids

    def test_noise_always_suppressed_regardless_of_threshold(self):
        """NOISE patterns (< 60%) are suppressed even if threshold=0."""
        p = self._make_pattern("tests", "x", "y", 3, 10)  # 30% → NOISE
        surviving, suppressed = apply_threshold_bands([p], threshold_pct=0)
        assert len(surviving) == 0
        assert len(suppressed) == 1

    def test_custom_threshold_80(self):
        patterns = [
            self._make_pattern("tests", "import_style", "named",   9, 10),  # 90% → surviving
            self._make_pattern("tests", "import_style", "default", 7, 10),  # 70% → suppressed at 80
        ]
        surviving, suppressed = apply_threshold_bands(patterns, threshold_pct=80)
        surviving_ids = {sp.pattern.pattern_id for sp in surviving}
        assert "tests/import_style/named" in surviving_ids
        assert "tests/import_style/default" not in surviving_ids

    def test_partition_is_complete(self):
        """Every scored pattern appears in exactly one of surviving/suppressed."""
        patterns = [
            self._make_pattern("tests", "import_style", v, c, 10)
            for v, c in [("named", 9), ("default", 7), ("wildcard", 5), ("none", 3)]
        ]
        surviving, suppressed = apply_threshold_bands(patterns)
        all_input_ids = {p.pattern_id for p in patterns}
        all_output_ids = {sp.pattern.pattern_id for sp in surviving} | {
            sp.pattern.pattern_id for sp in suppressed
        }
        assert all_input_ids == all_output_ids, "Some patterns lost in partition"
