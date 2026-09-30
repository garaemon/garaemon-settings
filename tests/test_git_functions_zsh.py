"""Tests for the worktree functions in dotfiles/dot_zsh/git-functions.zsh.

The functions use only syntax that bash also accepts, so the tests source the
file from bash. peco is replaced by a stub that records its input and picks
the line named by PECO_PICK_PATTERN.
"""

import os
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_FUNCTIONS_ZSH = REPO_ROOT / "dotfiles" / "dot_zsh" / "git-functions.zsh"


def run_git(repo, *args):
    subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        env={**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null"},
    )


@pytest.fixture
def repo_with_worktrees(tmp_path):
    """Create a repo with worktrees: 'locked-branch' is locked, 'plain-branch' is not."""
    main_repo = tmp_path / "main"
    main_repo.mkdir()
    run_git(main_repo, "init", "-b", "main")
    run_git(
        main_repo,
        "-c", "user.name=test",
        "-c", "user.email=test@example.com",
        "commit", "--allow-empty", "-m", "init",
    )
    run_git(main_repo, "worktree", "add", str(tmp_path / "locked"), "-b", "locked-branch")
    run_git(main_repo, "worktree", "add", str(tmp_path / "plain"), "-b", "plain-branch")
    run_git(main_repo, "worktree", "lock", "--reason", "test", str(tmp_path / "locked"))
    return main_repo


@pytest.fixture
def stub_dir(tmp_path):
    stub_directory = tmp_path / "stubs"
    stub_directory.mkdir()
    peco_stub = stub_directory / "peco"
    peco_stub.write_text(
        '#!/bin/bash\n'
        'tee "$PECO_INPUT_FILE" | grep -m1 -- "$PECO_PICK_PATTERN"\n'
    )
    peco_stub.chmod(0o755)
    return stub_directory


def run_in_repo(repo, stub_dir, tmp_path, snippet, pick_pattern=""):
    test_env = os.environ.copy()
    test_env["PATH"] = f"{stub_dir}:{test_env['PATH']}"
    test_env["PECO_INPUT_FILE"] = str(tmp_path / "peco_input.txt")
    test_env["PECO_PICK_PATTERN"] = pick_pattern
    test_env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    return subprocess.run(
        ["bash", "-c", f'source "{GIT_FUNCTIONS_ZSH}"; {snippet}'],
        cwd=repo,
        env=test_env,
        capture_output=True,
        text=True,
    )


def test_should_list_branch_names_when_a_worktree_is_locked(
    repo_with_worktrees, stub_dir, tmp_path
):
    run_in_repo(
        repo_with_worktrees, stub_dir, tmp_path, "git-worktree-select", "plain-branch"
    )

    peco_input = (tmp_path / "peco_input.txt").read_text().split()
    assert "locked" not in peco_input


def test_should_list_the_locked_branch_name(repo_with_worktrees, stub_dir, tmp_path):
    run_in_repo(
        repo_with_worktrees, stub_dir, tmp_path, "git-worktree-select", "plain-branch"
    )

    peco_input = (tmp_path / "peco_input.txt").read_text().split()
    assert "locked-branch" in peco_input


def test_should_change_to_locked_worktree_when_it_is_selected(
    repo_with_worktrees, stub_dir, tmp_path
):
    result = run_in_repo(
        repo_with_worktrees,
        stub_dir,
        tmp_path,
        "git-worktree-select; pwd",
        "locked-branch",
    )

    assert result.stdout.strip().endswith("/locked")


def test_should_unlock_every_locked_worktree(repo_with_worktrees, stub_dir, tmp_path):
    run_in_repo(repo_with_worktrees, stub_dir, tmp_path, "git-worktree-unlock-all")

    porcelain_lines = subprocess.run(
        ["git", "-C", str(repo_with_worktrees), "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
    ).stdout
    assert not any(line.startswith("locked") for line in porcelain_lines.splitlines())


def test_should_report_nothing_to_unlock_when_no_worktree_is_locked(
    repo_with_worktrees, stub_dir, tmp_path
):
    run_in_repo(repo_with_worktrees, stub_dir, tmp_path, "git-worktree-unlock-all")

    result = run_in_repo(
        repo_with_worktrees, stub_dir, tmp_path, "git-worktree-unlock-all"
    )

    assert "No locked worktrees" in result.stdout
