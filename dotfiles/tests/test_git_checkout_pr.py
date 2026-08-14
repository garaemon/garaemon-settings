"""Tests for git-checkout-pr.

The script checks out a branch named the way GitHub shows it on a pull request
page, either "owner:branch" or a bare "branch". Remotes are simulated with bare
repositories reached over file://, so no network and no `gh` stub are needed.
"""

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
GIT_CHECKOUT_PR = REPO_ROOT / "dot_local" / "bin" / "executable_git-checkout-pr"

FORK_REMOTE = "garaemon"
FORK_BRANCH = "2026.08.01-fix-bug"
ORIGIN_BRANCH = "claude/google-auth-login-signup-qb1fqv"


@dataclass
class PullRequestFixture:
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


def run_checkout_pr(cwd, *args):
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    return subprocess.run(
        ["bash", str(GIT_CHECKOUT_PR), *args],
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
def pull_request(tmp_path):
    """Working repo cloned from someorg/repo.git with a garaemon remote.

    The origin carries a branch that a same repository pull request would show
    without an owner prefix. The fork carries that branch plus one of its own,
    which is what a pull request from a fork looks like.
    """
    seed = tmp_path / "seed"
    seed.mkdir()
    run_git(seed, "init", "-b", "main")
    configure_identity(seed)
    commit_file(seed, "README", "hi\n")

    run_git(seed, "checkout", "-b", ORIGIN_BRANCH)
    commit_file(seed, "origin-side.txt", "origin\n")
    run_git(seed, "checkout", "main")

    origin_bare = tmp_path / "forks" / "someorg" / "repo.git"
    origin_bare.parent.mkdir(parents=True)
    run_git(tmp_path, "clone", "--bare", str(seed), str(origin_bare))

    run_git(seed, "checkout", "-b", FORK_BRANCH)
    commit_file(seed, "fix.txt", "fix\n")

    fork_bare = tmp_path / "forks" / FORK_REMOTE / "repo.git"
    fork_bare.parent.mkdir(parents=True)
    run_git(tmp_path, "clone", "--bare", str(seed), str(fork_bare))

    repo = tmp_path / "work"
    run_git(tmp_path, "clone", f"file://{origin_bare}", str(repo))
    configure_identity(repo)
    run_git(repo, "remote", "add", FORK_REMOTE, f"file://{fork_bare}")

    return PullRequestFixture(
        repo=repo, seed=seed, fork_bare=fork_bare, origin_bare=origin_bare
    )


def push_new_fork_commit(pull_request, name="second.txt"):
    """Add a commit on the fork branch and publish it to the fork's bare repo."""
    run_git(pull_request.seed, "checkout", FORK_BRANCH)
    commit_file(pull_request.seed, name, "more\n")
    run_git(pull_request.seed, "push", str(pull_request.fork_bare), FORK_BRANCH)


class TestArgumentValidation:
    def test_should_print_usage_with_h_flag(self, pull_request):
        result = run_checkout_pr(pull_request.repo, "-h")
        assert result.returncode == 0, result.stderr
        assert "Usage: git checkout-pr" in result.stdout

    def test_should_fail_when_no_argument_given(self, pull_request):
        result = run_checkout_pr(pull_request.repo)
        assert result.returncode != 0
        assert "BRANCH" in result.stderr

    def test_should_fail_when_extra_arguments_given(self, pull_request):
        result = run_checkout_pr(pull_request.repo, ORIGIN_BRANCH, "extra")
        assert result.returncode != 0

    @pytest.mark.parametrize("spec", ["", f":{FORK_BRANCH}", f"{FORK_REMOTE}:"])
    def test_should_fail_when_remote_or_branch_is_empty(self, pull_request, spec):
        result = run_checkout_pr(pull_request.repo, spec)
        assert result.returncode != 0
        assert "empty" in result.stderr

    def test_should_fail_outside_git_repository(self, tmp_path):
        outside = tmp_path / "outside"
        outside.mkdir()
        result = run_checkout_pr(outside, ORIGIN_BRANCH)
        assert result.returncode != 0
        assert "Not inside a git repository" in result.stderr


class TestOwnerPrefixedBranch:
    def test_should_checkout_branch_from_the_named_remote(self, pull_request):
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(pull_request.repo) == FORK_BRANCH

    def test_should_name_local_branch_after_branch_part_only(self, pull_request):
        run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert f"{FORK_REMOTE}-{FORK_BRANCH}" not in local_branches(pull_request.repo)

    def test_should_set_upstream_to_the_named_remote(self, pull_request):
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert upstream_of(pull_request.repo, FORK_BRANCH) == f"{FORK_REMOTE}/{FORK_BRANCH}"

    def test_should_create_remote_tracking_ref(self, pull_request):
        run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        result = subprocess.run(
            ["git", "show-ref", "--verify", f"refs/remotes/{FORK_REMOTE}/{FORK_BRANCH}"],
            cwd=str(pull_request.repo),
            capture_output=True,
        )
        assert result.returncode == 0

    def test_should_fail_when_remote_does_not_exist(self, pull_request):
        result = run_checkout_pr(pull_request.repo, f"nobody:{FORK_BRANCH}")
        assert result.returncode != 0
        assert "No remote named 'nobody'" in result.stderr
        assert "git remote add nobody https://github.com/nobody/repo.git" in result.stderr

    def test_should_fail_when_branch_missing_on_remote(self, pull_request):
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:no-such-branch")
        assert result.returncode != 0
        assert "does not exist on" in result.stderr


class TestBareBranch:
    def test_should_checkout_bare_branch_from_origin(self, pull_request):
        result = run_checkout_pr(pull_request.repo, ORIGIN_BRANCH)
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(pull_request.repo) == ORIGIN_BRANCH
        assert upstream_of(pull_request.repo, ORIGIN_BRANCH) == f"origin/{ORIGIN_BRANCH}"

    def test_should_use_origin_for_bare_branch_even_when_fork_has_it(self, pull_request):
        """The fork carries the same branch, but a bare name means the base repository."""
        run_git(pull_request.repo, "fetch", FORK_REMOTE)
        result = run_checkout_pr(pull_request.repo, ORIGIN_BRANCH)
        assert result.returncode == 0, result.stdout + result.stderr
        assert upstream_of(pull_request.repo, ORIGIN_BRANCH) == f"origin/{ORIGIN_BRANCH}"

    def test_should_fail_when_bare_branch_missing_on_origin(self, pull_request):
        result = run_checkout_pr(pull_request.repo, FORK_BRANCH)
        assert result.returncode != 0
        assert "does not exist on" in result.stderr


class TestRerun:
    def test_should_succeed_when_run_twice(self, pull_request):
        run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert current_branch(pull_request.repo) == FORK_BRANCH

    def test_should_fast_forward_existing_branch_to_remote_tip(self, pull_request):
        run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        run_git(pull_request.repo, "checkout", "main")
        push_new_fork_commit(pull_request)
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert commit_message_at(pull_request.repo, "HEAD") == "add second.txt"

    def test_should_warn_when_local_branch_diverged(self, pull_request):
        run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        commit_file(pull_request.repo, "local.txt", "local\n")
        push_new_fork_commit(pull_request)
        result = run_checkout_pr(pull_request.repo, f"{FORK_REMOTE}:{FORK_BRANCH}")
        assert result.returncode == 0, result.stdout + result.stderr
        assert "diverged" in result.stderr
        assert commit_message_at(pull_request.repo, "HEAD") == "add local.txt"
