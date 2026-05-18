"""
test_boundary.py — contract tests for boundary.py parsers.

TDD order (per plan):
  1. test_rejects_unknown_language
  2. test_normalizes_ctags_kinds
"""
import pytest

from scripts.discover.boundary import (
    parse_ast_grep_stream,
    parse_ctags_json_lines,
    parse_bucket_name,
    normalize_ctags_kind,
)


# ---------------------------------------------------------------------------
# test_rejects_unknown_language
# ---------------------------------------------------------------------------

class TestRejectsUnknownLanguage:
    """parse_ast_grep_stream must fail-closed on unknown/unsupported languages."""

    def test_rejects_unknown_language(self):
        """An ast-grep record with an unknown language raises ValueError."""
        line = '{"path": "foo.xyz", "language": "cobol", "ruleId": "x", "text": "hello"}'
        with pytest.raises(ValueError, match="unknown language"):
            parse_ast_grep_stream(iter([line]))

    def test_accepts_known_language_typescript(self):
        line = '{"path": "src/foo.ts", "language": "typescript", "ruleId": "r1", "text": "x"}'
        results = parse_ast_grep_stream(iter([line]))
        assert len(results) == 1
        assert results[0].language == "typescript"

    def test_accepts_known_language_python(self):
        line = '{"path": "app/main.py", "language": "python", "ruleId": "r1", "text": "x"}'
        results = parse_ast_grep_stream(iter([line]))
        assert len(results) == 1

    def test_accepts_known_language_js_alias(self):
        """'js' is an accepted alias for javascript."""
        line = '{"path": "index.js", "language": "js", "ruleId": "r1", "text": "x"}'
        results = parse_ast_grep_stream(iter([line]))
        assert len(results) == 1

    def test_rejects_missing_path(self):
        """Records without a path field raise ValueError."""
        line = '{"language": "python", "ruleId": "r1", "text": "x"}'
        with pytest.raises(ValueError, match="missing 'path'"):
            parse_ast_grep_stream(iter([line]))

    def test_empty_stream_returns_empty_list(self):
        results = parse_ast_grep_stream(iter([]))
        assert results == []

    def test_skips_blank_lines(self):
        lines = [
            "",
            '{"path": "a.py", "language": "python", "ruleId": "r", "text": ""}',
            "   ",
        ]
        results = parse_ast_grep_stream(iter(lines))
        assert len(results) == 1

    def test_rejects_malformed_json(self):
        with pytest.raises(ValueError, match="malformed JSON"):
            parse_ast_grep_stream(iter(["{not json}"]))


# ---------------------------------------------------------------------------
# test_normalizes_ctags_kinds
# ---------------------------------------------------------------------------

class TestNormalizesCtagsKinds:
    """normalize_ctags_kind and parse_ctags_json_lines must map raw kinds correctly."""

    def test_normalizes_function(self):
        assert normalize_ctags_kind("function") == "function"

    def test_normalizes_func_alias(self):
        assert normalize_ctags_kind("func") == "function"

    def test_normalizes_method(self):
        assert normalize_ctags_kind("method") == "method"

    def test_normalizes_member_to_method(self):
        assert normalize_ctags_kind("member") == "method"

    def test_normalizes_class(self):
        assert normalize_ctags_kind("class") == "class"

    def test_normalizes_struct_to_class(self):
        assert normalize_ctags_kind("struct") == "class"

    def test_normalizes_interface_to_class(self):
        assert normalize_ctags_kind("interface") == "class"

    def test_normalizes_module(self):
        assert normalize_ctags_kind("module") == "module"

    def test_normalizes_namespace_to_module(self):
        assert normalize_ctags_kind("namespace") == "module"

    def test_normalizes_variable(self):
        assert normalize_ctags_kind("variable") == "variable"

    def test_normalizes_const_to_variable(self):
        assert normalize_ctags_kind("const") == "variable"

    def test_unknown_kind_returns_other(self):
        assert normalize_ctags_kind("widget") == "other"

    def test_case_insensitive(self):
        assert normalize_ctags_kind("FUNCTION") == "function"
        assert normalize_ctags_kind("Class") == "class"

    def test_parse_ctags_json_normalizes_kind(self):
        """parse_ctags_json_lines maps raw kind through normalize_ctags_kind."""
        lines = [
            '{"_type": "tag", "name": "MyClass", "path": "src/foo.py", "kind": "class", "line": 1}',
            '{"_type": "tag", "name": "my_fn", "path": "src/foo.py", "kind": "function", "line": 5}',
            '{"_type": "tag", "name": "iface", "path": "src/bar.ts", "kind": "interface", "line": 2}',
        ]
        syms = parse_ctags_json_lines(iter(lines))
        assert len(syms) == 3
        kinds = {s.name: s.kind for s in syms}
        assert kinds["MyClass"] == "class"
        assert kinds["my_fn"] == "function"
        assert kinds["iface"] == "class"   # interface → class

    def test_parse_ctags_skips_header_records(self):
        """Metadata records (_type != 'tag') are skipped."""
        lines = [
            '{"_type": "ptag", "name": "!_TAG_FILE_FORMAT", "path": "", "pattern": ""}',
            '{"_type": "tag", "name": "fn1", "path": "x.py", "kind": "function", "line": 1}',
        ]
        syms = parse_ctags_json_lines(iter(lines))
        assert len(syms) == 1

    def test_parse_ctags_empty_stream(self):
        assert parse_ctags_json_lines(iter([])) == []


# ---------------------------------------------------------------------------
# Bucket name validation
# ---------------------------------------------------------------------------

class TestParseBucketName:
    def test_accepts_valid_names(self):
        for name in ("tests", "http-handlers", "data_access", "cli-entrypoints", "a1b2"):
            assert parse_bucket_name(name) == name

    def test_rejects_uppercase(self):
        with pytest.raises(ValueError):
            parse_bucket_name("Tests")

    def test_rejects_slash(self):
        with pytest.raises(ValueError):
            parse_bucket_name("rm -rf /")

    def test_rejects_space(self):
        with pytest.raises(ValueError):
            parse_bucket_name("foo bar")

    def test_rejects_empty(self):
        with pytest.raises(ValueError):
            parse_bucket_name("")
