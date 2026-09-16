"""Tests for pairing a pull request with the repository that holds it.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import unittest
from unittest import mock

import commands
import list_commentable_lines
from list_commentable_lines import resolve_pull_request_target

PULL_REQUEST = {
    "number": 12,
    "html_url": "https://example/12",
    "base": {"ref": "main", "repo": {"full_name": "upstream/repo"}},
}


class ResolvePullRequestTargetTest(unittest.TestCase):
    """resolve_pull_request_target keeps the repository and number in step."""

    def patch_lookups(self, queried: dict[str, object] | None = None):
        """Patch every lookup the resolver makes, recording the queried repos."""
        return mock.patch.multiple(
            list_commentable_lines,
            read_open_pull_request=lambda: PULL_REQUEST,
            detect_repository=lambda: "contributor/repo",
            detect_head_reference=lambda: ("contributor", "feature"),
            query_open_pull_request=lambda repository, owner, branch: (
                (queried or {}).get(repository)
            ),
        )

    def test_takes_both_from_the_overrides(self) -> None:
        with self.patch_lookups():
            self.assertEqual(
                resolve_pull_request_target("owner/repo", 3), ("owner/repo", 3)
            )

    def test_takes_both_from_one_lookup(self) -> None:
        # The fork's own repository holds no pull request, so the pair has to
        # come from the repository the fork was made from.
        with self.patch_lookups():
            self.assertEqual(
                resolve_pull_request_target(None, None), ("upstream/repo", 12)
            )

    def test_pairs_an_explicit_number_with_the_repository_in_hand(self) -> None:
        # Not upstream/repo: --pr names a pull request of this checkout, and
        # pairing it with the branch's upstream pull request would read another
        # repository's diff.
        with self.patch_lookups():
            self.assertEqual(
                resolve_pull_request_target(None, 3), ("contributor/repo", 3)
            )

    def test_looks_up_the_number_on_the_repository_given(self) -> None:
        with self.patch_lookups({"owner/repo": {"number": 8}}):
            self.assertEqual(
                resolve_pull_request_target("owner/repo", None), ("owner/repo", 8)
            )

    def test_raises_when_the_repository_given_has_no_pull_request(self) -> None:
        with self.patch_lookups({}), self.assertRaises(RuntimeError):
            resolve_pull_request_target("owner/repo", None)

    def test_raises_when_the_branch_has_no_pull_request(self) -> None:
        with mock.patch.object(
            list_commentable_lines, "read_open_pull_request", lambda: None
        ), self.assertRaises(RuntimeError):
            resolve_pull_request_target(None, None)

    def test_raises_when_no_origin_remote_names_a_repository(self) -> None:
        with mock.patch.object(
            list_commentable_lines, "detect_repository", lambda: None
        ), self.assertRaises(RuntimeError):
            resolve_pull_request_target(None, 3)


if __name__ == "__main__":
    unittest.main()
