"""Command runners shared by the branch-review scripts.

Every git and GitHub call in this skill goes through here, so that two rules are
applied uniformly:

  - Failures raise with the command's own stderr attached, rather than a bare
    exit status, so a bad revision or a missing pull request says why.
  - `gh` runs against the host the repository actually points at, derived from
    the origin remote. Without that, a GitHub Enterprise checkout silently talks
    to github.com and reports that the pull request does not exist.
"""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Mapping, Sequence
from functools import lru_cache
from typing import Any
from urllib.parse import quote, urlsplit

GITHUB_HOST_VARIABLE = "GH_HOST"

# GitHub's own maximum page size, and a stop so that a server answering every
# page with a full one cannot spin this forever.
GITHUB_PAGE_SIZE = 100
MAX_PAGE_COUNT = 100


def run_command(
    args: Sequence[str],
    check: bool = True,
    env: Mapping[str, str] | None = None,
    input_text: str | None = None,
) -> str:
    """Run a command and return its stdout.

    Raises RuntimeError when check is true and the command fails; returns an
    empty string when check is false, so optional lookups can fall through.
    input_text, when given, is written to the command's stdin.
    """
    completed = subprocess.run(
        args, capture_output=True, text=True, env=env, input=input_text
    )
    if completed.returncode != 0:
        if not check:
            return ""
        message = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"{' '.join(args)}: {message}")
    return completed.stdout


def parse_host_from_remote_url(url: str | None) -> str | None:
    """Return the hostname in a git remote URL, or None when it carries no host.

    Handles both URL forms git accepts: a real URL (`https://host/owner/repo`,
    `ssh://git@host:2222/owner/repo`) and the scp-like shorthand
    (`git@host:owner/repo`), which urlsplit cannot parse on its own. Local paths
    return None.
    """
    url = (url or "").strip()
    if not url:
        return None
    if "://" in url:
        hostname = urlsplit(url).hostname
        return hostname.lower() if hostname else None
    # scp-like shorthand: [user@]host:path. git applies this form only when the
    # first colon precedes the first slash, which keeps a local path such as
    # /srv/git:mirror/repo.git from parsing as the host "/srv/git".
    user_and_host = url.split(":", 1)[0]
    if ":" not in url or "/" in user_and_host:
        return None
    # A Windows drive letter, as git reads "C:/src/repo": a path, not a host.
    if len(user_and_host) == 1 and url[2:3] in ("/", "\\"):
        return None
    host = user_and_host.rsplit("@", 1)[-1]
    return host.lower() if host else None


@lru_cache(maxsize=None)
def detect_github_host() -> str | None:
    """Return the GitHub host the origin remote points at, or None.

    Cached for the life of the process: the remote cannot change mid-review, and
    a single post_review.py run makes five `gh` calls that would otherwise each
    spawn a git subprocess to re-read the same value.
    """
    url = run_command(["git", "remote", "get-url", "origin"], check=False).strip()
    return parse_host_from_remote_url(url)


def build_gh_environment(
    host: str | None, base_environment: Mapping[str, str] | None = None
) -> dict[str, str]:
    """Return an environment for `gh` with GH_HOST set to host.

    An inherited GH_HOST is overridden rather than preserved: the repository
    under review is what decides which server to talk to. When no host could be
    detected the environment is left as it is, so an explicitly exported
    GH_HOST still wins over nothing at all.
    """
    environment = dict(os.environ if base_environment is None else base_environment)
    if host:
        environment[GITHUB_HOST_VARIABLE] = host
    return environment


def run_gh_command(
    args: Sequence[str],
    check: bool = True,
    input_text: str | None = None,
) -> str:
    """Run a `gh` command against the repository's own GitHub host."""
    return run_command(
        args,
        check=check,
        env=build_gh_environment(detect_github_host()),
        input_text=input_text,
    )


def parse_repository_from_remote_url(url: str | None) -> str | None:
    """Return "owner/name" for a GitHub remote URL, or None when it names none.

    Accepts the same URL forms as parse_host_from_remote_url. A URL without a
    host is a local path, whose last two segments would otherwise parse as a
    repository.
    """
    if parse_host_from_remote_url(url) is None:
        return None
    url = (url or "").strip()
    path = urlsplit(url).path if "://" in url else url.split(":", 1)[1]
    segments = [segment for segment in path.split("/") if segment]
    if len(segments) < 2:
        return None
    owner, name = segments[-2], segments[-1]
    return f"{owner}/{name[: -len('.git')] if name.endswith('.git') else name}"


@lru_cache(maxsize=None)
def detect_repository() -> str | None:
    """Return the "owner/name" the origin remote points at, or None."""
    url = run_command(["git", "remote", "get-url", "origin"], check=False).strip()
    return parse_repository_from_remote_url(url)


def split_upstream_reference(upstream: str, local_branch: str) -> tuple[str, str]:
    """Return the (remote, branch) an `@{upstream}` value names.

    A value without a slash comes from `branch.<name>.remote = .`, a branch that
    tracks another local branch and so names no remote. That case and an unset
    upstream both fall back to origin and the local branch name.
    """
    remote, separator, remote_branch = upstream.partition("/")
    if not separator:
        return "origin", local_branch
    return remote, remote_branch or local_branch


@lru_cache(maxsize=None)
def detect_head_reference() -> tuple[str, str] | None:
    """Return (owner, branch) naming where the current branch lives on GitHub.

    The owner comes from the remote the branch tracks rather than from origin,
    because create-pr pushes a fork branch while origin stays the upstream
    repository. Returns None on a detached HEAD or a remote-less checkout.
    """
    local_branch = run_command(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"], check=False
    ).strip()
    if not local_branch or local_branch == "HEAD":
        return None
    upstream = run_command(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"],
        check=False,
    ).strip()
    remote, branch = split_upstream_reference(upstream, local_branch)
    url = run_command(["git", "remote", "get-url", remote], check=False).strip()
    repository = parse_repository_from_remote_url(url)
    if repository is None:
        return None
    return repository.split("/", 1)[0], branch


def build_open_pull_request_path(repository: str, owner: str, branch: str) -> str:
    """Return the REST path listing the open pull requests for a head branch."""
    return f"repos/{repository}/pulls?state=open&head={quote(f'{owner}:{branch}')}"


def carries_review_fields(candidate: Any) -> bool:
    """Return whether a REST list entry holds every field the review reads."""
    if not isinstance(candidate, dict):
        return False
    if not isinstance(candidate.get("number"), int):
        return False
    if not isinstance(candidate.get("html_url"), str):
        return False
    base = candidate.get("base")
    if not isinstance(base, dict) or not isinstance(base.get("ref"), str):
        return False
    repository = base.get("repo")
    return isinstance(repository, dict) and isinstance(repository.get("full_name"), str)


def select_open_pull_request(output: str) -> dict[str, Any] | None:
    """Return one pull request from a REST list response, or None.

    Entries missing a field the review reads are dropped here, so a caller can
    index the result rather than repeat the same guards. GitHub can list several
    open pull requests for one head branch; the highest number is the most
    recently opened, which is the branch's current review.
    """
    if not output.strip():
        return None
    try:
        payload = json.loads(output)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, list):
        return None
    pull_requests = [entry for entry in payload if carries_review_fields(entry)]
    if not pull_requests:
        return None
    return max(pull_requests, key=lambda pull_request: pull_request["number"])


def query_open_pull_request(
    repository: str, owner: str, branch: str
) -> dict[str, Any] | None:
    """Return the open pull request one repository lists for a head branch."""
    output = run_gh_command(
        ["gh", "api", build_open_pull_request_path(repository, owner, branch)],
        check=False,
    )
    return select_open_pull_request(output)


def read_parent_repository(repository: str) -> str | None:
    """Return the repository a fork was made from, or None when it is no fork."""
    parent = run_gh_command(
        ["gh", "api", f"repos/{repository}", "--jq", ".parent.full_name // empty"],
        check=False,
    ).strip()
    return parent or None


def read_open_pull_request() -> dict[str, Any] | None:
    """Return the open pull request for the current branch, or None.

    Reads the REST API rather than `gh pr view`, whose --json flag goes through
    GraphQL. Some hosted environments, Claude Code on the web among them, allow
    the REST API and refuse GraphQL.
    """
    repository = detect_repository()
    head = detect_head_reference()
    if repository is None or head is None:
        return None
    owner, branch = head
    pull_request = query_open_pull_request(repository, owner, branch)
    if pull_request is not None:
        return pull_request
    # A checkout whose origin is the fork lists no pull request of its own: the
    # pull request sits on the repository the fork was made from.
    parent = read_parent_repository(repository)
    if parent is None or parent == repository:
        return None
    return query_open_pull_request(parent, owner, branch)


def build_page_path(path: str, page: int) -> str:
    """Return a REST collection path asking for one page of GITHUB_PAGE_SIZE."""
    separator = "&" if "?" in path else "?"
    return f"{path}{separator}per_page={GITHUB_PAGE_SIZE}&page={page}"


def read_paginated_api(path: str) -> list[Any]:
    """Return every item of a REST collection, walking the pages by number.

    `gh api --paginate` follows the Link header, whose URLs name the repository
    by numeric id (repositories/{id}/...). The proxy in front of Claude Code on
    the web refuses that form, so the first page beyond the cut-off fails there.
    Asking for page N by number keeps every request on the repos/{owner}/{repo}
    path that both accept.
    """
    items: list[Any] = []
    for page in range(1, MAX_PAGE_COUNT + 1):
        output = run_gh_command(["gh", "api", build_page_path(path, page), "--jq", ".[]"])
        page_items = [json.loads(line) for line in output.splitlines() if line.strip()]
        items.extend(page_items)
        if len(page_items) < GITHUB_PAGE_SIZE:
            return items
    raise RuntimeError(f"{path}: more than {MAX_PAGE_COUNT} pages; refusing to keep asking")
