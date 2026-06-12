from aidp.detect import detect_project


def test_detects_python_uv_project(tmp_path):
    (tmp_path / "pyproject.toml").write_text(
        "[project]\nname = 'example'\n",
        encoding="utf-8",
    )

    profile = detect_project(tmp_path)

    assert profile.languages == ("python",)
    assert profile.package_manager == "uv"
    assert profile.commands["test"] == ("uv", "run", "pytest", "-q")
    assert profile.commands["doctor"] == ("python", "-m", "aidp", "doctor")


def test_detects_pnpm_scripts_from_package_json(tmp_path):
    (tmp_path / "package.json").write_text(
        '{"packageManager":"pnpm@10.0.0","scripts":{"test":"vitest run","lint":"eslint .","build":"tsc --noEmit"}}',
        encoding="utf-8",
    )

    profile = detect_project(tmp_path)

    assert profile.languages == ("typescript",)
    assert profile.package_manager == "pnpm"
    assert profile.commands["test"] == ("pnpm", "test")
    assert profile.commands["lint"] == ("pnpm", "lint")
    assert profile.commands["typecheck"] == ("pnpm", "build")


def test_detects_rust_and_go_projects(tmp_path):
    (tmp_path / "Cargo.toml").write_text("[package]\nname='r'\n", encoding="utf-8")
    (tmp_path / "go.mod").write_text("module example.com/g\n", encoding="utf-8")

    profile = detect_project(tmp_path)

    assert profile.languages == ("go", "rust")
    assert profile.commands["test"] == ("cargo", "test")
    assert profile.commands["go_test"] == ("go", "test", "./...")


def test_unknown_project_has_no_test_command(tmp_path):
    profile = detect_project(tmp_path)

    assert profile.languages == ()
    assert profile.package_manager is None
    assert "test" not in profile.commands
