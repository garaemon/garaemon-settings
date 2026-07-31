"""Tests for the git-worktree-add-with-branch zsh function.

The function lives in dot_zsh/git-functions.zsh. It takes a name, creates a
worktree at <main-repo-root>/.worktrees/<name> on a branch named <name>, and
cds into it. We test it end-to-end by sourcing the file in zsh inside a temp
git repo.
"""

import os
import shlex
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_FUNCTIONS = REPO_ROOT / "dot_zsh" / "git-functions.zsh"


def run_git(cwd, *args):
    return subprocess.run(
        ["git", *args], cwd=str(cwd), check=True, capture_output=True,
        text=True,
    )


def run_function(cwd, *args):
    quoted_args = " ".join(shlex.quote(a) for a in args)
    script = (
        f"source {shlex.quote(str(GIT_FUNCTIONS))} "
        f"&& git-worktree-add-with-branch {quoted_args} && pwd"
    )
    return subprocess.run(
        ["zsh", "-c", script],
        cwd=str(cwd),
        env=os.environ.copy(),
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


class TestGitWorktreeAddWithBranch:
    def test_should_create_worktree_under_worktrees_directory(self, repo):
        result = run_function(repo, "foo")
        assert result.returncode == 0, result.stdout + result.stderr
        assert (repo / ".worktrees" / "foo").is_dir()

    def test_should_create_branch_named_after_argument(self, repo):
        result = run_function(repo, "foo")
        assert result.returncode == 0, result.stdout + result.stderr
        branch = run_git(
            repo / ".worktrees" / "foo", "branch", "--show-current"
        ).stdout.strip()
        assert branch == "foo"

    def test_should_end_up_in_worktree_directory(self, repo):
        result = run_function(repo, "foo")
        assert result.returncode == 0, result.stdout + result.stderr
        final_pwd = result.stdout.strip().splitlines()[-1]
        expected_dir = repo / ".worktrees" / "foo"
        assert Path(final_pwd).resolve() == expected_dir.resolve()

    def test_should_resolve_main_repo_root_from_inside_another_worktree(
        self, repo
    ):
        first = run_function(repo, "foo")
        assert first.returncode == 0, first.stdout + first.stderr
        second = run_function(repo / ".worktrees" / "foo", "bar")
        assert second.returncode == 0, second.stdout + second.stderr
        assert (repo / ".worktrees" / "bar").is_dir()

    def test_should_reuse_existing_worktree_directory(self, repo):
        first = run_function(repo, "foo")
        assert first.returncode == 0, first.stdout + first.stderr
        second = run_function(repo, "foo")
        assert second.returncode == 0, second.stdout + second.stderr
        final_pwd = second.stdout.strip().splitlines()[-1]
        expected_dir = repo / ".worktrees" / "foo"
        assert Path(final_pwd).resolve() == expected_dir.resolve()

    def test_should_check_out_existing_branch(self, repo):
        run_git(repo, "branch", "foo")
        result = run_function(repo, "foo")
        assert result.returncode == 0, result.stdout + result.stderr
        branch = run_git(
            repo / ".worktrees" / "foo", "branch", "--show-current"
        ).stdout.strip()
        assert branch == "foo"

    def test_should_fail_when_no_argument_given(self, repo):
        result = run_function(repo)
        assert result.returncode != 0

    def test_should_fail_outside_git_repository(self, tmp_path):
        outside = tmp_path / "not-a-repo"
        outside.mkdir()
        result = run_function(outside, "foo")
        assert result.returncode != 0
