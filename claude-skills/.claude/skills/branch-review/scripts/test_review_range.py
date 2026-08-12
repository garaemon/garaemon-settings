"""Tests for turning a user's range request into a git diff range.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import unittest

from gather_review_context import (
    build_last_range,
    format_diff_spec,
    parse_range_spec,
)


class ParseRangeSpecTest(unittest.TestCase):
    """parse_range_spec splits a range into its two endpoints."""

    def test_reads_a_two_dot_range(self) -> None:
        self.assertEqual(parse_range_spec("abc123..def456"), ("abc123", "def456", False))

    def test_reads_a_three_dot_range_as_merge_base(self) -> None:
        # git spells "since we diverged" as three dots; the left endpoint is
        # then the merge-base, not the named revision.
        self.assertEqual(parse_range_spec("main...HEAD"), ("main", "HEAD", True))

    def test_defaults_the_right_endpoint_to_head(self) -> None:
        self.assertEqual(parse_range_spec("abc123"), ("abc123", "HEAD", False))

    def test_defaults_an_open_ended_range_to_head(self) -> None:
        self.assertEqual(parse_range_spec("abc123.."), ("abc123", "HEAD", False))

    def test_rejects_a_missing_left_endpoint(self) -> None:
        with self.assertRaises(ValueError):
            parse_range_spec("..HEAD")

    def test_rejects_an_empty_spec(self) -> None:
        with self.assertRaises(ValueError):
            parse_range_spec("   ")


class BuildLastRangeTest(unittest.TestCase):
    """build_last_range turns a commit count into a range ending at HEAD."""

    def test_builds_a_range_for_the_most_recent_commit(self) -> None:
        self.assertEqual(build_last_range(1), ("HEAD~1", "HEAD"))

    def test_builds_a_range_for_several_commits(self) -> None:
        self.assertEqual(build_last_range(3), ("HEAD~3", "HEAD"))

    def test_rejects_zero_commits(self) -> None:
        with self.assertRaises(ValueError):
            build_last_range(0)

    def test_rejects_a_negative_count(self) -> None:
        with self.assertRaises(ValueError):
            build_last_range(-2)


class FormatDiffSpecTest(unittest.TestCase):
    """format_diff_spec renders the endpoints as a git range."""

    def test_joins_the_endpoints_with_two_dots(self) -> None:
        self.assertEqual(format_diff_spec("abc123", "HEAD"), "abc123..HEAD")


if __name__ == "__main__":
    unittest.main()
