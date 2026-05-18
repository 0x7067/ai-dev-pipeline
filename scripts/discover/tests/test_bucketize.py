"""
test_bucketize.py — contract tests for core/bucket.py.

TDD order (per plan):
  3. test_globs_total_and_disjoint
"""
import pytest

from scripts.discover.core.bucket import (
    assign_bucket,
    bucketize_paths,
    BUCKET_RULES,
    KNOWN_BUCKETS,
)


class TestGlobsTotalAndDisjoint:
    """Bucket rules must be collectively exhaustive over their intended domains
    and disjoint (first-match-wins, so each file+kind lands in at most one bucket).
    """

    def test_each_bucket_rule_has_unique_name(self):
        names = [r.name for r in BUCKET_RULES]
        assert len(names) == len(set(names)), "Duplicate bucket names in BUCKET_RULES"

    def test_known_buckets_matches_rules(self):
        rule_names = {r.name for r in BUCKET_RULES}
        assert KNOWN_BUCKETS == rule_names

    def test_tests_bucket_matches_test_path(self):
        assert assign_bucket("src/tests/test_foo.py", "function") == "tests"

    def test_tests_bucket_matches_spec_extension(self):
        assert assign_bucket("src/foo.spec.ts", "function") == "tests"

    def test_tests_bucket_matches_underscore_test(self):
        assert assign_bucket("pkg/foo_test.go", "function") == "tests"

    def test_http_handlers_bucket(self):
        assert assign_bucket("app/handlers/user.py", "function") == "http-handlers"

    def test_http_handlers_filters_class_kind(self):
        # http-handlers only allows function/method kinds
        assert assign_bucket("app/handlers/user.py", "class") is None

    def test_background_jobs_bucket(self):
        assert assign_bucket("workers/email_worker.py", "function") == "background-jobs"

    def test_cli_entrypoints_bucket(self):
        assert assign_bucket("cmd/main.go", "function") == "cli-entrypoints"

    def test_data_access_bucket_class(self):
        assert assign_bucket("db/models/user.py", "class") == "data-access"

    def test_data_access_bucket_function(self):
        assert assign_bucket("models/repository.py", "function") == "data-access"

    def test_data_access_filters_variable(self):
        # data-access only allows class/function
        assert assign_bucket("db/models/user.py", "variable") is None

    def test_utilities_bucket(self):
        assert assign_bucket("lib/string_utils.py", "function") == "utilities"

    def test_utilities_filters_class(self):
        # utilities only allows function
        assert assign_bucket("utils/helpers.py", "class") is None

    def test_unbucketed_returns_none(self):
        assert assign_bucket("random/deep/path/file.py", "function") is None

    def test_first_match_wins_tests_over_lib(self):
        """A file in tests/ that also matches utilities pattern goes to tests (first-match)."""
        # tests patterns come before utilities in BUCKET_RULES
        assert assign_bucket("lib/tests/test_utils.py", "function") == "tests"

    def test_bucketize_paths_groups_correctly(self):
        paths = [
            ("src/tests/test_foo.py", "function"),
            ("app/handlers/user.py", "function"),
            ("app/handlers/admin.py", "method"),
            ("random/file.py", "function"),   # unbucketed
        ]
        result = bucketize_paths(paths)
        assert set(result["tests"]) == {"src/tests/test_foo.py"}
        assert set(result["http-handlers"]) == {
            "app/handlers/user.py",
            "app/handlers/admin.py",
        }
        assert "random/file.py" not in str(result)

    def test_bucketize_with_target_filter(self):
        paths = [
            ("src/tests/test_foo.py", "function"),
            ("app/handlers/user.py", "function"),
        ]
        result = bucketize_paths(paths, target_bucket="tests")
        assert "tests" in result
        assert "http-handlers" not in result

    def test_bucketize_empty_input(self):
        assert bucketize_paths([]) == {}
