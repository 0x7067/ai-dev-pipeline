from aidp.context_pack import build_context_pack


def test_context_pack_references_small_text_files_by_line_span(tmp_path):
    (tmp_path / "README.md").write_text("one\ntwo\nthree\n", encoding="utf-8")

    pack = build_context_pack(tmp_path, paths=("README.md",), max_file_bytes=100)

    assert len(pack.sources) == 1
    assert pack.sources[0].path == "README.md"
    assert pack.sources[0].purpose == "selected context"
    assert pack.sources[0].spans == ("1-3",)
    assert pack.omitted == ()


def test_context_pack_omits_binary_and_large_files(tmp_path):
    (tmp_path / "asset.bin").write_bytes(b"\x00\x01\x02")
    (tmp_path / "large.txt").write_text("x" * 20, encoding="utf-8")

    pack = build_context_pack(
        tmp_path,
        paths=("asset.bin", "large.txt"),
        max_file_bytes=10,
    )

    assert pack.sources == ()
    assert "binary: asset.bin" in pack.omitted
    assert "large: large.txt (20 bytes > 10)" in pack.omitted


def test_context_pack_caps_file_count(tmp_path):
    for index in range(3):
        (tmp_path / f"f{index}.txt").write_text("ok\n", encoding="utf-8")

    pack = build_context_pack(
        tmp_path,
        paths=("f0.txt", "f1.txt", "f2.txt"),
        max_files=2,
    )

    assert tuple(source.path for source in pack.sources) == ("f0.txt", "f1.txt")
    assert pack.omitted == ("file-cap: f2.txt",)
