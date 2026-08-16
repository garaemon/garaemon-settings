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

import os
import subprocess
from collections.abc import Mapping, Sequence
from urllib.parse import urlsplit

GITHUB_HOST_VARIABLE = "GH_HOST"


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
    # scp-like shorthand: [user@]host:path, where the path is not absolute.
    if ":" in url:
        location = url.split(":", 1)[0]
        host = location.rsplit("@", 1)[-1]
        return host.lower() if host else None
    return None


def detect_github_host() -> str | None:
    """Return the GitHub host the origin remote points at, or None."""
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
    host: str | None = None,
    input_text: str | None = None,
) -> str:
    """Run a `gh` command against the repository's own GitHub host."""
    resolved_host = host or detect_github_host()
    return run_command(
        args,
        check=check,
        env=build_gh_environment(resolved_host),
        input_text=input_text,
    )
