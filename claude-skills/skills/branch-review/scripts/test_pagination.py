"""Tests for walking a paginated REST collection by page number.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import json
import unittest
from unittest import mock

import commands
from commands import GITHUB_PAGE_SIZE, build_page_path, read_paginated_api


def build_page(item_count: int, first_index: int = 0) -> str:
    """Return item_count items as the newline-delimited JSON `--jq .[]` emits."""
    return "".join(
        json.dumps({"index": first_index + offset}) + "\n"
        for offset in range(item_count)
    )


class BuildPagePathTest(unittest.TestCase):
    """build_page_path asks for one page of a REST collection."""

    def test_starts_the_query_on_a_bare_path(self) -> None:
        self.assertEqual(
            build_page_path("repos/owner/repo/pulls/7/files", 1),
            "repos/owner/repo/pulls/7/files?per_page=100&page=1",
        )

    def test_extends_a_path_that_already_carries_a_query(self) -> None:
        self.assertEqual(
            build_page_path("repos/owner/repo/pulls?state=open", 2),
            "repos/owner/repo/pulls?state=open&per_page=100&page=2",
        )


class ReadPaginatedApiTest(unittest.TestCase):
    """read_paginated_api concatenates the pages it asks for by number."""

    def run_read(self, pages: list[str]) -> tuple[list, list[str]]:
        """Run the read against canned pages, returning the items and paths."""
        paths: list[str] = []

        def fake_run_gh_command(args, check=True, input_text=None):
            paths.append(args[2])
            index = len(paths) - 1
            return pages[index] if index < len(pages) else ""

        with mock.patch.object(commands, "run_gh_command", fake_run_gh_command):
            return read_paginated_api("repos/owner/repo/pulls/7/files"), paths

    def test_returns_the_items_of_a_single_short_page(self) -> None:
        items, _ = self.run_read([build_page(3)])
        self.assertEqual(len(items), 3)

    def test_stops_asking_after_a_short_page(self) -> None:
        _, paths = self.run_read([build_page(3)])
        self.assertEqual(len(paths), 1)

    def test_asks_for_the_next_page_after_a_full_one(self) -> None:
        items, _ = self.run_read(
            [build_page(GITHUB_PAGE_SIZE), build_page(11, GITHUB_PAGE_SIZE)]
        )
        self.assertEqual(len(items), GITHUB_PAGE_SIZE + 11)

    def test_numbers_the_pages_it_asks_for(self) -> None:
        # The page number is what keeps every request on the repos/{owner}/{repo}
        # path, rather than the numeric-id URL the Link header carries.
        _, paths = self.run_read([build_page(GITHUB_PAGE_SIZE), build_page(1)])
        self.assertEqual([path.rsplit("=", 1)[-1] for path in paths], ["1", "2"])

    def test_returns_nothing_for_an_empty_collection(self) -> None:
        items, paths = self.run_read([""])
        self.assertEqual(items, [])
        self.assertEqual(len(paths), 1)

    def test_refuses_to_follow_an_endless_collection(self) -> None:
        full_pages = [build_page(GITHUB_PAGE_SIZE)] * (commands.MAX_PAGE_COUNT + 1)
        with self.assertRaises(RuntimeError):
            self.run_read(full_pages)


if __name__ == "__main__":
    unittest.main()
