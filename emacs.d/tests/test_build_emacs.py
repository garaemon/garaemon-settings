"""Tests for scripts/build_emacs.py.

Functions that would clone Emacs, run a compiler, or reach the network are
replaced with monkeypatch, so no test builds anything.
"""

import hashlib
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

    def test_should_exit_2_for_unknown_native_compilation(self):
        result = run_script(["--native-compilation", "jit"])
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

    def test_should_default_jobs_to_available_cpus(self, monkeypatch):
        monkeypatch.setattr(build_emacs, "count_available_cpus", lambda: 64)
        options = build_emacs.parse_arguments([])
        assert options.jobs == 64


class TestCountAvailableCpus:
    def test_should_count_cpus_in_affinity_mask(self, monkeypatch):
        monkeypatch.setattr(
            build_emacs.os, "sched_getaffinity", lambda pid: {0, 1, 2},
            raising=False,
        )
        assert build_emacs.count_available_cpus() == 3

    def test_should_fall_back_to_cpu_count_without_affinity(
        self, monkeypatch
    ):
        monkeypatch.delattr(build_emacs.os, "sched_getaffinity", raising=False)
        monkeypatch.setattr(build_emacs.os, "cpu_count", lambda: 12)
        assert build_emacs.count_available_cpus() == 12

    def test_should_return_one_when_cpu_count_is_unknown(self, monkeypatch):
        monkeypatch.delattr(build_emacs.os, "sched_getaffinity", raising=False)
        monkeypatch.setattr(build_emacs.os, "cpu_count", lambda: None)
        assert build_emacs.count_available_cpus() == 1


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

    def test_should_require_libgccjit_when_aot_is_requested(
        self, monkeypatch
    ):
        arguments = self.build_arguments(
            monkeypatch, argv=["--native-compilation", "aot"], gccjit=False
        )
        assert "--with-native-compilation=aot" in arguments

    def test_should_tolerate_missing_images_for_auto_gui(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, gtk3=True)
        assert "--with-xpm=ifavailable" in arguments

    def test_should_require_images_for_explicit_pgtk(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, argv=["--gui", "pgtk"])
        assert not any(
            argument.endswith("=ifavailable") and "gnutls" not in argument
            for argument in arguments
        )

    def test_should_require_gnutls_when_requested(self, monkeypatch):
        arguments = self.build_arguments(monkeypatch, argv=["--gnutls", "yes"])
        assert "--with-gnutls=yes" in arguments

    def test_should_skip_native_compilation_when_disabled(self, monkeypatch):
        arguments = self.build_arguments(
            monkeypatch, argv=["--native-compilation", "no"], gccjit=True
        )
        assert "--with-native-compilation=no" in arguments


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
        probed_compilers = []

        def probe_terminal_library(compiler_path):
            probed_compilers.append(compiler_path)
            return has_terminal_library

        monkeypatch.setattr(
            build_emacs, "has_terminal_library", probe_terminal_library
        )
        return build_emacs.list_missing_requirements(), probed_compilers

    def test_should_report_missing_compiler(self, monkeypatch):
        missing, _ = self.list_missing(
            monkeypatch, missing_commands=("cc", "gcc")
        )
        assert missing == ["gcc"]

    def test_should_report_missing_terminal_library(self, monkeypatch):
        missing, _ = self.list_missing(
            monkeypatch, has_terminal_library=False
        )
        assert missing == ["libncurses-dev"]

    def test_should_report_nothing_when_all_present(self, monkeypatch):
        missing, _ = self.list_missing(monkeypatch)
        assert missing == []

    def test_should_probe_with_gcc_when_cc_is_missing(self, monkeypatch):
        _, probed_compilers = self.list_missing(
            monkeypatch, missing_commands=("cc",)
        )
        assert probed_compilers == ["/bin/gcc"]


class TestDownload:
    URL = "https://example.invalid/a.tar.xz"
    CONTENT = b"release"
    CONTENT_SHA256 = hashlib.sha256(CONTENT).hexdigest()

    @pytest.fixture
    def fetched_urls(self, monkeypatch):
        urls = []

        def fake_fetch_url(url, destination):
            urls.append(url)
            destination.write_bytes(self.CONTENT)

        monkeypatch.setattr(build_emacs, "fetch_url", fake_fetch_url)
        return urls

    def test_should_reject_checksum_mismatch(self, tmp_path, fetched_urls):
        with pytest.raises(SystemExit):
            build_emacs.download_verified(self.URL, "0" * 64, tmp_path / "a")

    def test_should_remove_file_on_checksum_mismatch(
        self, tmp_path, fetched_urls
    ):
        destination = tmp_path / "a"
        with pytest.raises(SystemExit):
            build_emacs.download_verified(self.URL, "0" * 64, destination)
        assert not destination.exists()

    def test_should_keep_file_when_checksum_matches(
        self, tmp_path, fetched_urls
    ):
        destination = tmp_path / "a"
        build_emacs.download_verified(
            self.URL, self.CONTENT_SHA256, destination
        )
        assert destination.read_bytes() == self.CONTENT

    def test_should_reuse_verified_cached_file(self, tmp_path, fetched_urls):
        destination = tmp_path / "a"
        destination.write_bytes(self.CONTENT)
        build_emacs.download_verified(
            self.URL, self.CONTENT_SHA256, destination
        )
        assert fetched_urls == []

    def test_should_refetch_corrupt_cached_file(self, tmp_path, fetched_urls):
        destination = tmp_path / "a"
        destination.write_bytes(b"truncated")
        build_emacs.download_verified(
            self.URL, self.CONTENT_SHA256, destination
        )
        assert fetched_urls == [self.URL]


class TestCheckoutEmacsSource:
    @pytest.fixture
    def git_calls(self, monkeypatch):
        calls = []
        monkeypatch.setattr(
            build_emacs, "run", lambda command, **kwargs: calls.append(command)
        )
        return calls

    def stub_shallow_answer(self, monkeypatch, answer):
        monkeypatch.setattr(
            build_emacs.subprocess,
            "run",
            lambda *args, **kwargs: subprocess.CompletedProcess(
                args, 0, stdout=f"{answer}\n"
            ),
        )

    def test_should_clone_shallowly_when_source_is_missing(
        self, tmp_path, git_calls
    ):
        build_emacs.checkout_emacs_source(tmp_path / "emacs", "emacs-31.1")
        assert git_calls[0][:5] == [
            "git", "clone", "--depth", "1", "--branch"
        ]

    def test_should_keep_full_clone_history(
        self, monkeypatch, tmp_path, git_calls
    ):
        (tmp_path / ".git").mkdir()
        self.stub_shallow_answer(monkeypatch, "false")
        build_emacs.checkout_emacs_source(tmp_path, "emacs-31.1")
        assert "--depth" not in git_calls[0]

    def test_should_keep_shallow_clone_shallow(
        self, monkeypatch, tmp_path, git_calls
    ):
        (tmp_path / ".git").mkdir()
        self.stub_shallow_answer(monkeypatch, "true")
        build_emacs.checkout_emacs_source(tmp_path, "emacs-31.1")
        assert "--depth" in git_calls[0]

    def test_should_check_out_fetched_revision(
        self, monkeypatch, tmp_path, git_calls
    ):
        (tmp_path / ".git").mkdir()
        self.stub_shallow_answer(monkeypatch, "false")
        build_emacs.checkout_emacs_source(tmp_path, "emacs-31.1")
        assert git_calls[1][-3:] == ["checkout", "--detach", "FETCH_HEAD"]


class TestMakeVariables:
    def build_variables(self, monkeypatch, available_commands):
        monkeypatch.setattr(
            build_emacs.shutil,
            "which",
            lambda name: f"/bin/{name}" if name in available_commands else None,
        )
        return build_emacs.build_make_variables()

    def test_should_wrap_gcc_with_ccache(self, monkeypatch):
        variables = self.build_variables(monkeypatch, ("ccache", "gcc", "cc"))
        assert variables == ["CC=ccache gcc"]

    def test_should_wrap_cc_when_gcc_is_missing(self, monkeypatch):
        variables = self.build_variables(monkeypatch, ("ccache", "cc"))
        assert variables == ["CC=ccache cc"]

    def test_should_leave_compiler_alone_without_ccache(self, monkeypatch):
        variables = self.build_variables(monkeypatch, ("gcc", "cc"))
        assert variables == []


class TestEnsureTreeSitter:
    @pytest.fixture
    def commands(self, monkeypatch, tmp_path):
        calls = []
        monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path))
        monkeypatch.setattr(build_emacs, "succeeds", lambda command, **kw: False)
        monkeypatch.setattr(
            build_emacs, "run", lambda command, **kwargs: calls.append(command)
        )
        return calls

    def ensure(self, monkeypatch, head_commit):
        monkeypatch.setattr(
            build_emacs, "read_head_commit", lambda repository: head_commit
        )
        build_emacs.ensure_tree_sitter(Path("/opt/e"), 2, env={})

    def test_should_install_pinned_commit(self, monkeypatch, commands):
        self.ensure(monkeypatch, build_emacs.TREE_SITTER_COMMIT)
        assert commands[-1][-1] == "install"

    def test_should_stop_on_unexpected_commit(self, monkeypatch, commands):
        with pytest.raises(SystemExit):
            self.ensure(monkeypatch, "0" * 40)

    def test_should_not_build_unexpected_commit(self, monkeypatch, commands):
        with pytest.raises(SystemExit):
            self.ensure(monkeypatch, "0" * 40)
        assert all(command[0] != "make" for command in commands)


class TestBuildEnvironment:
    GCC_LIBRARY_DIR = "/usr/lib/gcc/x86_64-linux-gnu/13"

    @pytest.fixture
    def env(self, monkeypatch):
        monkeypatch.setattr(
            build_emacs.shutil, "which", lambda name: f"/usr/bin/{name}"
        )
        monkeypatch.setattr(
            build_emacs.subprocess,
            "run",
            lambda *args, **kwargs: subprocess.CompletedProcess(
                args, 0, stdout=f"{self.GCC_LIBRARY_DIR}/libgcc.a\n"
            ),
        )
        monkeypatch.delenv("LIBRARY_PATH", raising=False)
        monkeypatch.delenv("LDFLAGS", raising=False)
        return build_emacs.build_environment(Path("/opt/e"))

    def test_should_put_prefix_bin_first_on_path(self, env):
        assert env["PATH"].split(":")[0] == "/opt/e/bin"

    def test_should_search_prefix_pkgconfig(self, env):
        assert env["PKG_CONFIG_PATH"].split(":")[0] == "/opt/e/lib/pkgconfig"

    def test_should_embed_prefix_lib_as_runtime_path(self, env):
        assert "-Wl,-rpath,/opt/e/lib" in env["LDFLAGS"].split()

    def test_should_add_gcc_library_dir_to_library_path(self, env):
        assert env["LIBRARY_PATH"] == self.GCC_LIBRARY_DIR

    def test_should_link_against_gcc_library_dir(self, env):
        assert f"-L{self.GCC_LIBRARY_DIR}" in env["LDFLAGS"].split()


class TestEnsureBuildTools:
    def ensure(self, monkeypatch, missing_commands):
        installed_packages = []
        monkeypatch.setattr(
            build_emacs.shutil,
            "which",
            lambda name, path=None:
                None if name in missing_commands else f"/usr/bin/{name}",
        )
        monkeypatch.setattr(
            build_emacs,
            "install_gnu_package",
            lambda release, prefix, jobs, env:
                installed_packages.append(release.name),
        )
        build_emacs.ensure_build_tools(Path("/opt/e"), 2, env={"PATH": ""})
        return installed_packages

    def test_should_build_m4_before_autoconf_before_texinfo(
        self, monkeypatch
    ):
        installed = self.ensure(monkeypatch, ("m4", "autoconf", "makeinfo"))
        assert installed == ["m4", "autoconf", "texinfo"]

    def test_should_build_nothing_when_tools_exist(self, monkeypatch):
        assert self.ensure(monkeypatch, ()) == []

    def test_should_build_texinfo_for_missing_makeinfo(self, monkeypatch):
        assert self.ensure(monkeypatch, ("makeinfo",)) == ["texinfo"]


class TestRequiredFeatures:
    def assert_features(self, monkeypatch, argv, sqlite3):
        monkeypatch.setattr(build_emacs, "has_sqlite3", lambda env: sqlite3)
        options = build_emacs.parse_arguments(argv)
        build_emacs.assert_required_features(options, env={})

    def test_should_stop_when_required_sqlite_is_missing(self, monkeypatch):
        with pytest.raises(SystemExit):
            self.assert_features(monkeypatch, ["--sqlite", "yes"], False)

    def test_should_pass_when_required_sqlite_exists(self, monkeypatch):
        self.assert_features(monkeypatch, ["--sqlite", "yes"], True)

    def test_should_tolerate_missing_sqlite_by_default(self, monkeypatch):
        self.assert_features(monkeypatch, [], False)
