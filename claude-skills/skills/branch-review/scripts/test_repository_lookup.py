"""Tests for locating the repository and its open pull request over REST.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import unittest

from commands import (
    build_open_pull_request_path,
    parse_repository_from_remote_url,
    select_open_pull_request,
    split_upstream_reference,
)


def build_payload(*pull_requests: str) -> str:
    """Return a REST list response carrying the given JSON objects."""
    return f"[{', '.join(pull_requests)}]"


def build_pull_request(number: int) -> str:
    """Return one complete pull request object as JSON."""
    return (
        f'{{"number": {number}, "html_url": "https://example/{number}", '
        f'"base": {{"ref": "main"}}}}'
    )


class ParseRepositoryFromRemoteUrlTest(unittest.TestCase):
    """parse_repository_from_remote_url reads "owner/name" from a remote URL."""

    def test_reads_an_https_url(self) -> None:
        self.assertEqual(
            parse_repository_from_remote_url("https://github.com/owner/repo"),
            "owner/repo",
        )

    def test_strips_the_git_suffix(self) -> None:
        self.assertEqual(
            parse_repository_from_remote_url("https://github.com/owner/repo.git"),
            "owner/repo",
        )

    def test_reads_an_scp_style_ssh_url(self) -> None:
        self.assertEqual(
            parse_repository_from_remote_url("git@github.com:owner/repo.git"),
            "owner/repo",
        )

    def test_reads_an_ssh_url_with_a_port(self) -> None:
        self.assertEqual(
            parse_repository_from_remote_url(
                "ssh://git@github.example.com:2222/owner/repo.git"
            ),
            "owner/repo",
        )

    def test_ignores_a_trailing_slash(self) -> None:
        self.assertEqual(
            parse_repository_from_remote_url("https://github.com/owner/repo/"),
            "owner/repo",
        )

    def test_keeps_the_case_of_the_repository(self) -> None:
        # GitHub resolves either case, but the name is echoed into REVIEW.md,
        # so it should read the way the remote spells it.
        self.assertEqual(
            parse_repository_from_remote_url("https://github.com/Owner/RepoName"),
            "Owner/RepoName",
        )

    def test_returns_none_for_a_local_path(self) -> None:
        # Without this guard the last two path segments of /srv/git/repo.git
        # would parse as the repository "git/repo".
        self.assertIsNone(parse_repository_from_remote_url("/srv/git/repo.git"))

    def test_returns_none_when_the_path_names_no_owner(self) -> None:
        self.assertIsNone(parse_repository_from_remote_url("https://github.com/repo"))

    def test_returns_none_for_an_empty_url(self) -> None:
        self.assertIsNone(parse_repository_from_remote_url(""))


class BuildOpenPullRequestPathTest(unittest.TestCase):
    """build_open_pull_request_path builds the REST query for a head branch."""

    def test_filters_by_state_and_head(self) -> None:
        self.assertEqual(
            build_open_pull_request_path("owner/repo", "owner", "feature"),
            "repos/owner/repo/pulls?state=open&head=owner%3Afeature",
        )

    def test_keeps_slashes_in_a_branch_name(self) -> None:
        # Slashes separate nothing inside a query value, and leaving them
        # readable keeps a failing call easy to replay by hand.
        self.assertEqual(
            build_open_pull_request_path("owner/repo", "owner", "claude/fix-1"),
            "repos/owner/repo/pulls?state=open&head=owner%3Aclaude/fix-1",
        )

    def test_escapes_a_branch_name_that_would_break_the_query(self) -> None:
        self.assertEqual(
            build_open_pull_request_path("owner/repo", "owner", "fix&state=closed"),
            "repos/owner/repo/pulls?state=open&head=owner%3Afix%26state%3Dclosed",
        )

    def test_names_the_head_owner_of_a_fork(self) -> None:
        # create-pr pushes to a fork while origin stays the upstream repository,
        # so the head owner and the queried repository differ.
        self.assertEqual(
            build_open_pull_request_path("upstream/repo", "contributor", "feature"),
            "repos/upstream/repo/pulls?state=open&head=contributor%3Afeature",
        )


class SplitUpstreamReferenceTest(unittest.TestCase):
    """split_upstream_reference reads the remote and branch out of @{upstream}."""

    def test_splits_a_remote_tracking_branch(self) -> None:
        self.assertEqual(
            split_upstream_reference("origin/feature", "feature"), ("origin", "feature")
        )

    def test_keeps_slashes_in_the_branch_name(self) -> None:
        self.assertEqual(
            split_upstream_reference("fork/claude/fix-1", "claude/fix-1"),
            ("fork", "claude/fix-1"),
        )

    def test_falls_back_to_origin_when_no_upstream_is_set(self) -> None:
        self.assertEqual(split_upstream_reference("", "feature"), ("origin", "feature"))

    def test_falls_back_to_origin_for_a_local_tracking_branch(self) -> None:
        # `branch.<name>.remote = .` tracks another local branch, so @{upstream}
        # is a bare branch name. Reading it as a remote would ask git for the
        # URL of a remote named "main".
        self.assertEqual(split_upstream_reference("main", "feature"), ("origin", "feature"))


class SelectOpenPullRequestTest(unittest.TestCase):
    """select_open_pull_request reads one pull request out of a REST response."""

    def test_returns_the_only_pull_request(self) -> None:
        payload = build_payload(build_pull_request(7))
        self.assertEqual(select_open_pull_request(payload)["number"], 7)

    def test_returns_none_for_an_empty_list(self) -> None:
        self.assertIsNone(select_open_pull_request("[]"))

    def test_returns_none_for_empty_output(self) -> None:
        # run_gh_command returns "" when the call fails and check is false.
        self.assertIsNone(select_open_pull_request(""))

    def test_returns_none_for_malformed_json(self) -> None:
        self.assertIsNone(select_open_pull_request("not json"))

    def test_returns_none_when_the_response_is_not_a_list(self) -> None:
        self.assertIsNone(select_open_pull_request('{"message": "Not Found"}'))

    def test_prefers_the_newest_pull_request(self) -> None:
        # GitHub can list more than one open pull request for a head branch;
        # the most recently opened one is the branch's current review.
        payload = build_payload(build_pull_request(3), build_pull_request(9))
        self.assertEqual(select_open_pull_request(payload)["number"], 9)

    def test_drops_a_pull_request_missing_a_field_the_review_reads(self) -> None:
        # The caller indexes html_url and base.ref, so an entry without them
        # must not be selected.
        payload = build_payload('{"number": 9}', build_pull_request(3))
        self.assertEqual(select_open_pull_request(payload)["number"], 3)

    def test_returns_none_when_every_entry_is_incomplete(self) -> None:
        self.assertIsNone(select_open_pull_request('[{"number": 9}]'))

    def test_returns_none_for_a_list_of_non_objects(self) -> None:
        self.assertIsNone(select_open_pull_request("[1, 2]"))


if __name__ == "__main__":
    unittest.main()
