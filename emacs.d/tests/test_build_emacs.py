"""Tests for scripts/build_emacs.py.

Functions that would clone Emacs, run a compiler, or reach the network are
replaced with monkeypatch, so no test builds anything.
"""

import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import build_emacs  # noqa: E402


def write_fake_emacs(prefix, version):
    """Place an emacs stub under prefix/bin that reports version."""
    bin_dir = prefix / "bin"
    bin_dir.mkdir(parents=True)
    emacs_path = bin_dir / "emacs"
    emacs_path.write_text(f'#!/bin/sh\nprintf "%s" "{version}"\n')
    emacs_path.chmod(0o755)


def run_script(args):
    """Run build_emacs.py as a program with the given argument list."""
    return subprocess.run(
        [sys.executable, str(SCRIPTS_DIR / "build_emacs.py"), *args],
        capture_output=True,
        text=True,
    )


class TestArguments:
    def test_should_print_usage_for_help(self):
        result = run_script(["--help"])
        assert "usage: build_emacs.py" in result.stdout

    def test_should_exit_2_for_unknown_argument(self):
        result = run_script(["--nope"])
        assert result.returncode == 2

    def test_should_exit_2_for_unknown_gui(self):
        result = run_script(["--gui", "motif"])
        assert result.returncode == 2

    def test_should_default_prefix_to_home_local(self, monkeypatch, tmp_path):
        monkeypatch.setenv("HOME", str(tmp_path))
        options = build_emacs.parse_arguments([])
        assert options.prefix == tmp_path / ".local"

    def test_should_default_source_under_ghq(self, monkeypatch, tmp_path):
        monkeypatch.setenv("HOME", str(tmp_path))
        monkeypatch.delenv("GHQ_ROOT", raising=False)
        options = build_emacs.parse_arguments([])
        assert options.source_dir == (
            tmp_path / "ghq" / "github.com" / "emacs-mirror" / "emacs"
        )

    def test_should_honor_ghq_root(self, monkeypatch, tmp_path):
        monkeypatch.setenv("GHQ_ROOT", str(tmp_path / "src"))
        options = build_emacs.parse_arguments([])
        assert options.source_dir == (
            tmp_path / "src" / "github.com" / "emacs-mirror" / "emacs"
        )

    def test_should_cap_default_jobs(self, monkeypatch):
        monkeypatch.setattr(build_emacs.os, "cpu_count", lambda: 64)
        options = build_emacs.parse_arguments([])
        assert options.jobs == build_emacs.MAX_DEFAULT_JOBS


class TestVersionComparison:
    def test_should_strip_emacs_prefix(self):
        assert build_emacs.extract_numeric_version("emacs-31.1") == "31.1"

    def test_should_return_none_for_branch_name(self):
        assert build_emacs.extract_numeric_version("master") is None

    @pytest.mark.parametrize(
        "installed, required",
        [("31.1", "31.1"), ("31.2", "31.1"), ("32.0.50", "31.1"),
         ("31.10", "31.9")],
    )
    def test_should_accept_same_or_newer(self, installed, required):
        assert build_emacs.is_version_at_least(installed, required)

    @pytest.mark.parametrize(
        "installed, required", [("30.2", "31.1"), ("31.0.91", "31.1")]
    )
    def test_should_reject_older(self, installed, required):
        assert not build_emacs.is_version_at_least(installed, required)


class TestCheckOnly:
    def test_should_exit_zero_when_installed_emacs_is_current(self, tmp_path):
        write_fake_emacs(tmp_path, "31.1")
        result = run_script(["--check", "--prefix", str(tmp_path)])
        assert result.returncode == 0

    def test_should_exit_10_when_installed_emacs_is_old(self, tmp_path):
        write_fake_emacs(tmp_path, "30.2")
        result = run_script(["--check", "--prefix", str(tmp_path)])
        assert result.returncode == 10

    def test_should_exit_10_when_emacs_is_missing(self, tmp_path):
        result = run_script(["--check", "--prefix", str(tmp_path)])
        assert result.returncode == 10

    def test_should_exit_10_for_branch_name(self, tmp_path):
        write_fake_emacs(tmp_path, "99.1")
        result = run_script(
            ["--check", "--version", "master", "--prefix", str(tmp_path)]
        )
        assert result.returncode == 10

    def test_should_exit_10_when_forced(self, tmp_path):
        write_fake_emacs(tmp_path, "31.1")
        result = run_script(
            ["--check", "--force", "--prefix", str(tmp_path)]
        )
        assert result.returncode == 10


class TestConfigureArguments:
    def build_arguments(self, monkeypatch, argv=(), gtk3=True, gccjit=True):
        monkeypatch.setattr(build_emacs, "has_gtk3", lambda env: gtk3)
        monkeypatch.setattr(
            build_emacs, "has_usable_libgccjit", lambda env: gccjit
        )
        options = build_emacs.parse_arguments(list(argv))
        return build_emacs.build_configure_arguments(options, env={})

    def test_should_install_into_prefix(self, monkeypatch):
        arguments = self.build_arguments(
            monkeypatch, argv=["--prefix", "/opt/e"]
        )
        assert "--prefix=/opt/e" in arguments

    def test_should_pick_pgtk_when_gtk3_exists(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, gtk3=True)
        assert "--with-pgtk" in arguments

    def test_should_build_terminal_only_without_gtk3(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, gtk3=False)
        assert "--without-x" in arguments

    def test_should_honor_gui_none_even_with_gtk3(self, monkeypatch):
        arguments = self.build_arguments(
            monkeypatch, argv=["--gui", "none"], gtk3=True
        )
        assert "--with-pgtk" not in arguments

    def test_should_force_pgtk_when_requested(self, monkeypatch):
        arguments = self.build_arguments(
            monkeypatch, argv=["--gui", "pgtk"], gtk3=False
        )
        assert "--with-pgtk" in arguments

    def test_should_compile_ahead_of_time_with_libgccjit(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, gccjit=True)
        assert "--with-native-compilation=aot" in arguments

    def test_should_disable_native_compilation_without_libgccjit(
        self, monkeypatch
    ):
        arguments = self.build_arguments(monkeypatch, gccjit=False)
        assert "--with-native-compilation=no" in arguments

    def test_should_tolerate_missing_gnutls(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch)
        assert "--with-gnutls=ifavailable" in arguments


class TestCleanStaleBuildTree:
    @pytest.fixture
    def git_calls(self, monkeypatch):
        calls = []
        monkeypatch.setattr(
            build_emacs, "run", lambda command, **kwargs: calls.append(command)
        )
        return calls

    def clean(self, tmp_path, stamp_content):
        if stamp_content is not None:
            (tmp_path / build_emacs.BUILD_STAMP_NAME).write_text(stamp_content)
        build_emacs.clean_stale_build_tree(tmp_path, "emacs-31.1")

    def test_should_clean_when_stamp_is_missing(self, tmp_path, git_calls):
        self.clean(tmp_path, None)
        assert git_calls == [["git", "-C", str(tmp_path), "clean", "-xdf"]]

    def test_should_clean_when_stamp_names_another_version(
        self, tmp_path, git_calls
    ):
        self.clean(tmp_path, "emacs-30.2\n")
        assert len(git_calls) == 1

    def test_should_keep_tree_when_stamp_matches(self, tmp_path, git_calls):
        self.clean(tmp_path, "emacs-31.1\n")
        assert git_calls == []

    def test_should_stamp_the_cleaned_tree(self, tmp_path, git_calls):
        self.clean(tmp_path, "emacs-30.2\n")
        stamp_path = tmp_path / build_emacs.BUILD_STAMP_NAME
        assert stamp_path.read_text() == "emacs-31.1\n"


class TestMissingRequirements:
    def list_missing(self, monkeypatch, missing_commands=(),
                     has_terminal_library=True):
        monkeypatch.setattr(
            build_emacs.shutil,
            "which",
            lambda name: None if name in missing_commands else f"/bin/{name}",
        )
        monkeypatch.setattr(
            build_emacs,
            "has_terminal_library",
            lambda: has_terminal_library,
        )
        return build_emacs.list_missing_requirements()

    def test_should_report_missing_compiler(self, monkeypatch):
        missing = self.list_missing(monkeypatch, missing_commands=("cc", "gcc"))
        assert missing == ["gcc"]

    def test_should_report_missing_terminal_library(self, monkeypatch):
        missing = self.list_missing(monkeypatch, has_terminal_library=False)
        assert missing == ["libncurses-dev"]

    def test_should_report_nothing_when_all_present(self, monkeypatch):
        assert self.list_missing(monkeypatch) == []


class TestDownload:
    def test_should_reject_checksum_mismatch(self, monkeypatch, tmp_path):
        monkeypatch.setattr(
            build_emacs,
            "fetch_url",
            lambda url, destination: destination.write_bytes(b"tampered"),
        )
        with pytest.raises(SystemExit):
            build_emacs.download_verified(
                "https://example.invalid/a.tar.xz", "0" * 64, tmp_path / "a"
            )
