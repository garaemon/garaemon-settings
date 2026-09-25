"""Tests for scripts/build-emacs.sh.

Each test sources build-emacs.sh to call one function in isolation. Commands
with side effects (git, emacs, pkg-config) are replaced by stub executables
or shell functions, so no test clones Emacs or runs a compiler.
"""

import os
import subprocess
from pathlib import Path

import pytest


BUILD_EMACS_SH = (
    Path(__file__).resolve().parent.parent / "scripts" / "build-emacs.sh"
)


def write_stub(stub_dir, name, body):
    """Create an executable stub named name that runs the given bash body."""
    stub_path = stub_dir / name
    stub_path.write_text(f"#!/bin/bash\n{body}\n")
    stub_path.chmod(0o755)
    return stub_path


def source_and_run(snippet, home, stub_dir=None):
    """Source build-emacs.sh with HOME set to home, then run snippet."""
    test_env = os.environ.copy()
    test_env["HOME"] = str(home)
    test_env.pop("XDG_CACHE_HOME", None)
    test_env.pop("GHQ_ROOT", None)
    if stub_dir is not None:
        test_env["PATH"] = f"{stub_dir}:{test_env['PATH']}"
    full_script = f'source "{BUILD_EMACS_SH}"\n{snippet}'
    return subprocess.run(
        ["bash", "-c", full_script],
        env=test_env,
        capture_output=True,
        text=True,
    )


def run_script(args, home, stub_dir=None):
    """Run build-emacs.sh as a program with the given argument list."""
    test_env = os.environ.copy()
    test_env["HOME"] = str(home)
    if stub_dir is not None:
        test_env["PATH"] = f"{stub_dir}:{test_env['PATH']}"
    return subprocess.run(
        ["bash", str(BUILD_EMACS_SH), *args],
        env=test_env,
        capture_output=True,
        text=True,
    )


def install_fake_emacs(prefix, version):
    """Place an emacs stub under prefix/bin that reports version."""
    bin_dir = prefix / "bin"
    bin_dir.mkdir(parents=True)
    write_stub(bin_dir, "emacs", f'printf "%s" "{version}"')


@pytest.fixture
def stub_dir(tmp_path):
    directory = tmp_path / "stubs"
    directory.mkdir()
    return directory


class TestArguments:
    def test_should_print_usage_for_help(self, tmp_path):
        result = run_script(["--help"], tmp_path)
        assert "Usage: build-emacs.sh" in result.stdout

    def test_should_exit_zero_for_help(self, tmp_path):
        result = run_script(["--help"], tmp_path)
        assert result.returncode == 0

    def test_should_exit_2_for_unknown_argument(self, tmp_path):
        result = run_script(["--nope"], tmp_path)
        assert result.returncode == 2

    def test_should_exit_2_for_unknown_gui(self, tmp_path):
        result = run_script(["--gui", "motif"], tmp_path)
        assert result.returncode == 2

    def test_should_exit_2_for_missing_option_value(self, tmp_path):
        result = run_script(["--version"], tmp_path)
        assert result.returncode == 2

    def test_should_default_prefix_to_home_local(self, tmp_path):
        result = source_and_run(
            'parse_arguments; printf "%s" "${INSTALL_PREFIX}"', tmp_path
        )
        assert result.stdout == f"{tmp_path}/.local"

    def test_should_default_source_under_ghq(self, tmp_path):
        result = source_and_run(
            'parse_arguments; printf "%s" "${SOURCE_DIR}"', tmp_path
        )
        assert result.stdout == (
            f"{tmp_path}/ghq/github.com/emacs-mirror/emacs"
        )

    def test_should_accept_option_with_equals(self, tmp_path):
        result = source_and_run(
            'parse_arguments --version=emacs-30.2; printf "%s" "${EMACS_VERSION}"',
            tmp_path,
        )
        assert result.stdout == "emacs-30.2"


class TestVersionComparison:
    def test_should_strip_emacs_prefix(self, tmp_path):
        result = source_and_run(
            "extract_numeric_version emacs-31.1", tmp_path
        )
        assert result.stdout == "31.1"

    def test_should_print_nothing_for_branch_name(self, tmp_path):
        result = source_and_run("extract_numeric_version master", tmp_path)
        assert result.stdout == ""

    @pytest.mark.parametrize(
        "installed, required",
        [("31.1", "31.1"), ("31.2", "31.1"), ("32.0.50", "31.1")],
    )
    def test_should_accept_same_or_newer(self, tmp_path, installed, required):
        result = source_and_run(
            f"is_version_at_least {installed} {required}", tmp_path
        )
        assert result.returncode == 0

    @pytest.mark.parametrize(
        "installed, required", [("30.2", "31.1"), ("31.0.91", "31.1")]
    )
    def test_should_reject_older(self, tmp_path, installed, required):
        result = source_and_run(
            f"is_version_at_least {installed} {required}", tmp_path
        )
        assert result.returncode == 1


class TestCheckOnly:
    def test_should_exit_zero_when_installed_emacs_is_current(self, tmp_path):
        install_fake_emacs(tmp_path / "prefix", "31.1")
        result = run_script(
            ["--check", "--prefix", str(tmp_path / "prefix")], tmp_path
        )
        assert result.returncode == 0

    def test_should_exit_10_when_installed_emacs_is_old(self, tmp_path):
        install_fake_emacs(tmp_path / "prefix", "30.2")
        result = run_script(
            ["--check", "--prefix", str(tmp_path / "prefix")], tmp_path
        )
        assert result.returncode == 10

    def test_should_exit_10_when_emacs_is_missing(self, tmp_path):
        result = run_script(
            ["--check", "--prefix", str(tmp_path / "prefix")], tmp_path
        )
        assert result.returncode == 10

    def test_should_exit_10_for_branch_name(self, tmp_path):
        install_fake_emacs(tmp_path / "prefix", "99.1")
        result = run_script(
            ["--check", "--version", "master",
             "--prefix", str(tmp_path / "prefix")],
            tmp_path,
        )
        assert result.returncode == 10

    def test_should_exit_10_when_forced(self, tmp_path):
        install_fake_emacs(tmp_path / "prefix", "31.1")
        result = run_script(
            ["--check", "--force", "--prefix", str(tmp_path / "prefix")],
            tmp_path,
        )
        assert result.returncode == 10


class TestConfigureArguments:
    HARNESS = (
        "parse_arguments {args}\n"
        "has_gtk3() {{ return {gtk3}; }}\n"
        "has_usable_libgccjit() {{ return {gccjit}; }}\n"
        "build_configure_arguments\n"
    )

    def build_arguments(self, tmp_path, args="", gtk3=0, gccjit=0):
        snippet = self.HARNESS.format(args=args, gtk3=gtk3, gccjit=gccjit)
        return source_and_run(snippet, tmp_path).stdout.splitlines()

    def test_should_install_into_prefix(self, tmp_path):
        arguments = self.build_arguments(tmp_path, args="--prefix /opt/e")
        assert "--prefix=/opt/e" in arguments

    def test_should_pick_pgtk_when_gtk3_exists(self, tmp_path):
        arguments = self.build_arguments(tmp_path, gtk3=0)
        assert "--with-pgtk" in arguments

    def test_should_build_terminal_only_without_gtk3(self, tmp_path):
        arguments = self.build_arguments(tmp_path, gtk3=1)
        assert "--without-x" in arguments

    def test_should_honor_gui_none_even_with_gtk3(self, tmp_path):
        arguments = self.build_arguments(tmp_path, args="--gui none", gtk3=0)
        assert "--with-pgtk" not in arguments

    def test_should_force_pgtk_when_requested(self, tmp_path):
        arguments = self.build_arguments(tmp_path, args="--gui pgtk", gtk3=1)
        assert "--with-pgtk" in arguments

    def test_should_compile_ahead_of_time_with_libgccjit(self, tmp_path):
        arguments = self.build_arguments(tmp_path, gccjit=0)
        assert "--with-native-compilation=aot" in arguments

    def test_should_disable_native_compilation_without_libgccjit(
        self, tmp_path
    ):
        arguments = self.build_arguments(tmp_path, gccjit=1)
        assert "--with-native-compilation=no" in arguments

    def test_should_tolerate_missing_gnutls(self, tmp_path):
        arguments = self.build_arguments(tmp_path)
        assert "--with-gnutls=ifavailable" in arguments


class TestCleanStaleBuildTree:
    SNIPPET = (
        'git() {{ echo "GIT:$*"; }}\n'
        "parse_arguments --version emacs-31.1 --source-dir {source}\n"
        "clean_stale_build_tree\n"
    )

    def run_clean(self, tmp_path, stamp_content):
        source_dir = tmp_path / "emacs"
        source_dir.mkdir()
        if stamp_content is not None:
            (source_dir / ".built-emacs-version").write_text(stamp_content)
        result = source_and_run(
            self.SNIPPET.format(source=source_dir), tmp_path
        )
        return result, source_dir

    def test_should_clean_when_stamp_is_missing(self, tmp_path):
        result, _ = self.run_clean(tmp_path, None)
        assert "GIT:-C" in result.stdout and "clean -xdf" in result.stdout

    def test_should_clean_when_stamp_names_another_version(self, tmp_path):
        result, _ = self.run_clean(tmp_path, "emacs-30.2\n")
        assert "clean -xdf" in result.stdout

    def test_should_keep_tree_when_stamp_matches(self, tmp_path):
        result, _ = self.run_clean(tmp_path, "emacs-31.1\n")
        assert "clean" not in result.stdout

    def test_should_stamp_the_cleaned_tree(self, tmp_path):
        _, source_dir = self.run_clean(tmp_path, "emacs-30.2\n")
        stamp = (source_dir / ".built-emacs-version").read_text()
        assert stamp == "emacs-31.1\n"


class TestMissingRequirements:
    def test_should_report_missing_compiler(self, tmp_path, stub_dir):
        result = source_and_run(
            "command_exists() { [[ $1 != cc && $1 != gcc ]]; }\n"
            "has_terminal_library() { return 0; }\n"
            "list_missing_requirements",
            tmp_path,
            stub_dir,
        )
        assert "gcc" in result.stdout.splitlines()

    def test_should_report_missing_terminal_library(self, tmp_path):
        result = source_and_run(
            "command_exists() { return 0; }\n"
            "has_terminal_library() { return 1; }\n"
            "list_missing_requirements",
            tmp_path,
        )
        assert "libncurses-dev" in result.stdout.splitlines()

    def test_should_report_nothing_when_all_present(self, tmp_path):
        result = source_and_run(
            "command_exists() { return 0; }\n"
            "has_terminal_library() { return 0; }\n"
            "list_missing_requirements",
            tmp_path,
        )
        assert result.stdout == ""
