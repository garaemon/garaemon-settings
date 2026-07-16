"""Tests for the git-worktree-from-pr zsh function.

The function lives in dot_zsh/git-functions.zsh and depends on `gh` for the
PR list and `peco` for interactive selection. We test it end-to-end by
sourcing the file in zsh inside a temp git repo, with stub `gh` and `peco`
executables on PATH that behave deterministically and log their invocations.
"""

import os
import shlex
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_FUNCTIONS = REPO_ROOT / "dot_zsh" / "git-functions.zsh"


def run_git(cwd, *args):
    subprocess.run(
        ["git", *args], cwd=str(cwd), check=True, capture_output=True
    )


def install_fake_gh(bin_dir, log_file):
    """Drop a fake `gh` that serves a fixed PR list and logs every call."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(
        "#!/bin/bash\n"
        f"echo \"$@\" >> {shlex.quote(str(log_file))}\n"
        'case "$1 $2" in\n'
        '  "pr list")\n'
        "    printf '#12\\tfeature-branch\\tAdd feature\\n'\n"
        "    printf '#34\\tbugfix-branch\\tFix bug\\n'\n"
        "    ;;\n"
        '  "pr checkout")\n'
        "    ;;\n"
        "esac\n"
    )
    gh.chmod(0o755)


def install_fake_peco(bin_dir, pattern, log_file):
    """Drop a fake `peco` that picks the first stdin line containing pattern."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    peco = bin_dir / "peco"
    peco.write_text(
        "#!/bin/bash\n"
        f"echo peco-invoked >> {shlex.quote(str(log_file))}\n"
        f"grep -m1 -F -- {shlex.quote(pattern)}\n"
    )
    peco.chmod(0o755)


def run_function(repo, fake_bin, *args):
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
    quoted_args = " ".join(shlex.quote(a) for a in args)
    script = (
        f"source {shlex.quote(str(GIT_FUNCTIONS))} "
        f"&& git-worktree-from-pr {quoted_args} && pwd"
    )
    return subprocess.run(
        ["zsh", "-c", script],
        cwd=str(repo),
        env=env,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def repo(tmp_path):
    """Plain repo with a single commit on main."""
    repo = tmp_path / "repo"
    repo.mkdir()
    run_git(repo, "init", "-b", "main")
    run_git(repo, "config", "user.email", "test@example.com")
    run_git(repo, "config", "user.name", "test")
    (repo / "README").write_text("hi\n")
    run_git(repo, "add", "README")
    run_git(repo, "commit", "-m", "init")
    return repo


@pytest.fixture
def fake_bin(tmp_path):
    return tmp_path / "bin"


@pytest.fixture
def stub_log(tmp_path):
    return tmp_path / "stub.log"


class TestGitWorktreeFromPr:
    def test_should_create_worktree_for_selected_pr(
        self, repo, fake_bin, stub_log, tmp_path
    ):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "feature-branch", stub_log)
        result = run_function(repo, fake_bin)
        assert result.returncode == 0, result.stdout + result.stderr
        worktree_dir = tmp_path / "repo" / ".worktrees" / "pr-12"
        assert worktree_dir.is_dir()

    def test_should_checkout_pr_with_gh_inside_worktree(
        self, repo, fake_bin, stub_log
    ):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "feature-branch", stub_log)
        result = run_function(repo, fake_bin)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "pr checkout 12" in stub_log.read_text()

    def test_should_end_up_in_worktree_directory(
        self, repo, fake_bin, stub_log, tmp_path
    ):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "feature-branch", stub_log)
        result = run_function(repo, fake_bin)
        assert result.returncode == 0, result.stdout + result.stderr
        final_pwd = result.stdout.strip().splitlines()[-1]
        expected_dir = tmp_path / "repo" / ".worktrees" / "pr-12"
        assert Path(final_pwd).resolve() == expected_dir.resolve()

    def test_should_skip_peco_when_pr_number_is_given(
        self, repo, fake_bin, stub_log, tmp_path
    ):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "feature-branch", stub_log)
        result = run_function(repo, fake_bin, "34")
        assert result.returncode == 0, result.stdout + result.stderr
        assert (tmp_path / "repo" / ".worktrees" / "pr-34").is_dir()
        assert "peco-invoked" not in stub_log.read_text()

    def test_should_reuse_existing_worktree_directory(
        self, repo, fake_bin, stub_log, tmp_path
    ):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "feature-branch", stub_log)
        first = run_function(repo, fake_bin, "12")
        assert first.returncode == 0, first.stdout + first.stderr
        second = run_function(repo, fake_bin, "12")
        assert second.returncode == 0, second.stdout + second.stderr
        final_pwd = second.stdout.strip().splitlines()[-1]
        expected_dir = tmp_path / "repo" / ".worktrees" / "pr-12"
        assert Path(final_pwd).resolve() == expected_dir.resolve()

    def test_should_fail_when_no_pr_selected(self, repo, fake_bin, stub_log):
        install_fake_gh(fake_bin, stub_log)
        install_fake_peco(fake_bin, "no-such-line", stub_log)
        result = run_function(repo, fake_bin)
        assert result.returncode != 0
