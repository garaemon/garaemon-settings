"""Tests for git-select.

The script is bash and depends on `peco` for interactive selection. We test it
end-to-end by running it against a temp git repo with a stub `peco` on PATH
that picks a deterministic line from stdin.
"""

import os
import shlex
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_SELECT = REPO_ROOT / "dot_local" / "bin" / "executable_git-select"


def run_git(cwd, *args):
    subprocess.run(
        ["git", *args], cwd=str(cwd), check=True, capture_output=True
    )


def install_fake_peco(bin_dir, pattern):
    """Drop a fake `peco` in bin_dir that picks the first stdin line containing pattern."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    peco = bin_dir / "peco"
    peco.write_text(
        "#!/bin/bash\n"
        f"grep -m1 -F -- {shlex.quote(pattern)}\n"
    )
    peco.chmod(0o755)


def run_git_select(repo, fake_bin, *args):
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
    return subprocess.run(
        ["bash", str(GIT_SELECT), *args],
        cwd=str(repo),
        env=env,
        capture_output=True,
        text=True,
    )


def current_branch(repo):
    return subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=str(repo),
        text=True,
    ).strip()


@pytest.fixture
def repo(tmp_path):
    """Repo with main, two plain branches, and one branch checked out in another worktree."""
    repo = tmp_path / "repo"
    repo.mkdir()
    run_git(repo, "init", "-b", "main")
    run_git(repo, "config", "user.email", "test@example.com")
    run_git(repo, "config", "user.name", "test")
    (repo / "README").write_text("hi\n")
    run_git(repo, "add", "README")
    run_git(repo, "commit", "-m", "init")
    run_git(repo, "branch", "feature-a")
    run_git(repo, "branch", "feature-b")
    # A branch checked out in another worktree is shown as "+ branch" in
    # `git branch --list` output. This is what the regression is about.
    run_git(repo, "worktree", "add", str(tmp_path / "wt"), "-b", "worktree-branch")
    return repo


class TestGitSelect:
    def test_strips_worktree_marker_before_fetch(self, repo, tmp_path):
        """Regression: a branch checked out in another worktree appears as
        '+ branch' in `git branch --list`. Without stripping the '+', the name
        was passed to `git fetch` / `git checkout` and produced
        'fatal: invalid refspec ...'.
        """
        fake_bin = tmp_path / "bin"
        install_fake_peco(fake_bin, "worktree-branch")
        result = run_git_select(repo, fake_bin)
        combined = result.stdout + result.stderr
        # The exact symptom the user reported.
        assert "invalid refspec" not in combined
        # The malformed branch name must never reach git invocations or echos.
        assert "+ worktree-branch" not in combined
        # And the script must report the cleaned branch name when it acts on it.
        assert "Checking out 'worktree-branch'" in combined

    def test_strips_current_branch_marker(self, repo, tmp_path):
        """The current branch is marked with '* ' and must be stripped too."""
        fake_bin = tmp_path / "bin"
        install_fake_peco(fake_bin, "main")
        result = run_git_select(repo, fake_bin)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "* main" not in (result.stdout + result.stderr)
        assert current_branch(repo) == "main"

    def test_checks_out_plain_local_branch(self, repo, tmp_path):
        """A branch with only leading whitespace should check out cleanly."""
        fake_bin = tmp_path / "bin"
        install_fake_peco(fake_bin, "feature-a")
        result = run_git_select(repo, fake_bin)
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(repo) == "feature-a"

    def test_show_all_strips_worktree_marker(self, repo, tmp_path):
        """The -a path uses the same sed and must strip '+' as well."""
        fake_bin = tmp_path / "bin"
        install_fake_peco(fake_bin, "worktree-branch")
        result = run_git_select(repo, fake_bin, "-a")
        combined = result.stdout + result.stderr
        assert "invalid refspec" not in combined
        assert "+ worktree-branch" not in combined
