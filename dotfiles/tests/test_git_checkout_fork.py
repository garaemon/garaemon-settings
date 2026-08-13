"""Tests for git-checkout-fork.

The script resolves a GitHub pull request style "owner:branch" string to a
registered remote and checks the branch out locally. Forks are simulated with
bare repositories laid out as <owner>/<repo>.git, because the owner extraction
treats a file:// path exactly like a GitHub URL. No network and no `gh` stub
are needed.
"""

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_CHECKOUT_FORK = REPO_ROOT / "dot_local" / "bin" / "executable_git-checkout-fork"

FORK_OWNER = "garaemon"
ORIGIN_OWNER = "someorg"
FORK_BRANCH = "2026.08.01-fix-bug"


@dataclass
class ForkFixture:
    """Paths of a working repository and the bare repositories it points at."""

    repo: Path
    seed: Path
    fork_bare: Path
    origin_bare: Path


def run_git(cwd, *args):
    subprocess.run(["git", *args], cwd=str(cwd), check=True, capture_output=True)


def commit_file(repo, name, content):
    (Path(repo) / name).write_text(content)
    run_git(repo, "add", name)
    run_git(repo, "commit", "-m", f"add {name}")


def configure_identity(repo):
    run_git(repo, "config", "user.email", "test@example.com")
    run_git(repo, "config", "user.name", "test")


def run_checkout_fork(cwd, *args):
    env = os.environ.copy()
    # Keep unreachable hosts failing immediately instead of prompting or
    # waiting on a proxy: several cases point remotes at github.invalid.
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_SSH_COMMAND"] = "/bin/false"
    env["NO_PROXY"] = "*"
    for proxy_variable in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
        env.pop(proxy_variable, None)
    return subprocess.run(
        ["bash", str(GIT_CHECKOUT_FORK), *args],
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def current_branch(repo):
    return subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=str(repo), text=True
    ).strip()


def upstream_of(repo, branch):
    return subprocess.check_output(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", f"{branch}@{{upstream}}"],
        cwd=str(repo),
        text=True,
    ).strip()


def local_branches(repo):
    output = subprocess.check_output(
        ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads"],
        cwd=str(repo),
        text=True,
    )
    return output.split()


def commit_message_at(repo, revision):
    return subprocess.check_output(
        ["git", "log", "-1", "--format=%s", revision], cwd=str(repo), text=True
    ).strip()


@pytest.fixture
def fork(tmp_path):
    """Working repo cloned from someorg/repo.git with garaemon/repo.git as a remote.

    The fork carries an extra branch that the origin does not have, which is
    what a pull request from a fork looks like.
    """
    seed = tmp_path / "seed"
    seed.mkdir()
    run_git(seed, "init", "-b", "main")
    configure_identity(seed)
    commit_file(seed, "README", "hi\n")

    origin_bare = tmp_path / "forks" / ORIGIN_OWNER / "repo.git"
    origin_bare.parent.mkdir(parents=True)
    run_git(tmp_path, "clone", "--bare", str(seed), str(origin_bare))

    run_git(seed, "checkout", "-b", FORK_BRANCH)
    commit_file(seed, "fix.txt", "fix\n")

    fork_bare = tmp_path / "forks" / FORK_OWNER / "repo.git"
    fork_bare.parent.mkdir(parents=True)
    run_git(tmp_path, "clone", "--bare", str(seed), str(fork_bare))

    repo = tmp_path / "work"
    run_git(tmp_path, "clone", f"file://{origin_bare}", str(repo))
    configure_identity(repo)
    run_git(repo, "remote", "add", FORK_OWNER, f"file://{fork_bare}")

    return ForkFixture(repo=repo, seed=seed, fork_bare=fork_bare, origin_bare=origin_bare)


def push_new_fork_commit(fork, name="second.txt"):
    """Add a commit on the fork branch and publish it to the fork's bare repo."""
    run_git(fork.seed, "checkout", FORK_BRANCH)
    commit_file(fork.seed, name, "more\n")
    run_git(fork.seed, "push", str(fork.fork_bare), FORK_BRANCH)


class TestArgumentValidation:
    def test_should_print_usage_with_h_flag(self, fork):
        result = run_checkout_fork(fork.repo, "-h")
        assert result.returncode == 0, result.stderr
        assert "Usage: git checkout-fork" in result.stdout

    def test_should_fail_when_no_argument_given(self, fork):
        result = run_checkout_fork(fork.repo)
        assert result.returncode != 0
        assert "OWNER:BRANCH" in result.stderr

    def test_should_fail_when_argument_has_no_colon(self, fork):
        result = run_checkout_fork(fork.repo, FORK_OWNER)
        assert result.returncode != 0
        assert "OWNER:BRANCH" in result.stderr

    @pytest.mark.parametrize("spec", [f":{FORK_BRANCH}", f"{FORK_OWNER}:"])
    def test_should_fail_when_owner_or_branch_is_empty(self, fork, spec):
        result = run_checkout_fork(fork.repo, spec)
        assert result.returncode != 0
        assert "empty" in result.stderr

    def test_should_fail_when_branch_name_is_invalid(self, fork):
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:bad..name")
        assert result.returncode != 0
        assert "not a valid branch name" in result.stderr

    def test_should_fail_when_extra_arguments_given(self, fork):
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}", "extra")
        assert result.returncode != 0

    def test_should_fail_outside_git_repository(self, tmp_path):
        outside = tmp_path / "outside"
        outside.mkdir()
        result = run_checkout_fork(outside, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "Not inside a git repository" in result.stderr


class TestRemoteResolution:
    def test_should_checkout_branch_from_matching_remote(self, fork):
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(fork.repo) == FORK_BRANCH

    def test_should_name_local_branch_after_branch_part_only(self, fork):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert f"{FORK_OWNER}-{FORK_BRANCH}" not in local_branches(fork.repo)

    def test_should_set_upstream_to_fork_remote(self, fork):
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert upstream_of(fork.repo, FORK_BRANCH) == f"{FORK_OWNER}/{FORK_BRANCH}"

    def test_should_match_owner_case_insensitively(self, fork):
        result = run_checkout_fork(fork.repo, f"Garaemon:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(fork.repo) == FORK_BRANCH

    @pytest.mark.parametrize(
        "url",
        [
            f"git@github.invalid:{FORK_OWNER}/repo.git",
            f"ssh://git@github.invalid/{FORK_OWNER}/repo.git",
            f"ssh://git@github.invalid:22/{FORK_OWNER}/repo.git",
            f"https://github.invalid/{FORK_OWNER}/repo.git",
            f"https://github.invalid/{FORK_OWNER}/repo",
        ],
    )
    def test_should_resolve_owner_from_various_remote_url_forms(self, fork, url):
        """Only the resolution step is under test; the fetch that follows fails
        because the host does not exist."""
        run_git(fork.repo, "remote", "remove", FORK_OWNER)
        run_git(fork.repo, "remote", "add", "fork", url)
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert f"Using remote 'fork' for owner '{FORK_OWNER}'" in result.stdout
        assert "No remote points at" not in result.stderr

    def test_should_fail_when_no_remote_matches_owner(self, fork):
        result = run_checkout_fork(fork.repo, f"nobody:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "No remote points at owner 'nobody'" in result.stderr

    def test_should_suggest_remote_add_command_with_repository_name(self, fork):
        result = run_checkout_fork(fork.repo, f"nobody:{FORK_BRANCH}")
        assert "git remote add nobody https://github.com/nobody/repo.git" in result.stderr

    def test_should_fail_when_multiple_remotes_match_owner(self, fork):
        run_git(fork.repo, "remote", "rename", FORK_OWNER, "fork-file")
        run_git(fork.repo, "remote", "add", "fork-https", f"https://github.invalid/{FORK_OWNER}/repo.git")
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "fork-file" in result.stderr
        assert "fork-https" in result.stderr
        assert "-r" in result.stderr

    def test_should_prefer_remote_named_after_owner_when_ambiguous(self, fork):
        run_git(fork.repo, "remote", "add", "fork-https", f"https://github.invalid/{FORK_OWNER}/repo.git")
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert f"Using remote '{FORK_OWNER}'" in result.stdout

    def test_should_use_remote_given_by_r_option(self, fork):
        result = run_checkout_fork(fork.repo, "-r", FORK_OWNER, f"whoever:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(fork.repo) == FORK_BRANCH

    def test_should_fail_when_r_option_names_unknown_remote(self, fork):
        result = run_checkout_fork(fork.repo, "-r", "missing", f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "missing" in result.stderr


class TestFetchAndCheckout:
    def test_should_create_remote_tracking_ref(self, fork):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        result = subprocess.run(
            ["git", "show-ref", "--verify", f"refs/remotes/{FORK_OWNER}/{FORK_BRANCH}"],
            cwd=str(fork.repo),
            capture_output=True,
        )
        assert result.returncode == 0

    def test_should_fail_when_branch_missing_on_fork(self, fork):
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:no-such-branch")
        assert result.returncode != 0

    def test_should_succeed_when_run_twice(self, fork):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(fork.repo) == FORK_BRANCH

    def test_should_fast_forward_existing_branch_to_fork_tip(self, fork):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        run_git(fork.repo, "checkout", "main")
        push_new_fork_commit(fork)
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert commit_message_at(fork.repo, "HEAD") == "add second.txt"

    def test_should_warn_when_local_branch_diverged(self, fork):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        commit_file(fork.repo, "local.txt", "local\n")
        push_new_fork_commit(fork)
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert "diverged" in result.stderr
        assert commit_message_at(fork.repo, "HEAD") == "add local.txt"

    def test_should_fail_when_local_branch_tracks_different_remote(self, fork):
        run_git(fork.repo, "branch", FORK_BRANCH, "origin/main")
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "origin/main" in result.stderr

    def test_should_fail_when_local_branch_has_no_upstream(self, fork):
        run_git(fork.repo, "branch", "--no-track", FORK_BRANCH, "main")
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "nothing" in result.stderr

    def test_should_fail_when_branch_is_checked_out_in_another_worktree(self, fork, tmp_path):
        run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        run_git(fork.repo, "checkout", "main")
        worktree = tmp_path / "wt"
        run_git(fork.repo, "worktree", "add", str(worktree), FORK_BRANCH)
        result = run_checkout_fork(fork.repo, f"{FORK_OWNER}:{FORK_BRANCH}")
        assert result.returncode != 0
        assert str(worktree) in result.stderr
