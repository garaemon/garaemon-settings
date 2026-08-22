"""Tests for turning a user's range request into a git diff range.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock

import gather_review_context
from gather_review_context import (
    EMPTY_TREE_OBJECT,
    build_commit_range,
    build_last_range,
    format_diff_spec,
    parse_range_spec,
    resolve_explicit_range,
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


class BuildCommitRangeTest(unittest.TestCase):
    """build_commit_range covers one commit, including a parentless root commit."""

    def setUp(self) -> None:
        repository = tempfile.TemporaryDirectory()
        self.addCleanup(repository.cleanup)
        # build_commit_range reaches git through the process cwd rather than a
        # repository argument, so the test has to move into the fixture repo.
        # Restore first, then remove: cleanups run last-registered-first.
        original_directory = os.getcwd()
        self.addCleanup(os.chdir, original_directory)
        os.chdir(repository.name)
        self.run_git("init", "--quiet")
        self.run_git("config", "user.email", "test@example.com")
        self.run_git("config", "user.name", "Test")
        # A globally configured signing key would make every commit here fail.
        self.run_git("config", "commit.gpgsign", "false")
        self.commit("first")

    def run_git(self, *arguments: str) -> None:
        completed = subprocess.run(["git", *arguments], capture_output=True, text=True)
        if completed.returncode != 0:
            # CalledProcessError would report only the exit status, leaving a CI
            # failure (a hook, an unexpected global config) unexplained.
            self.fail(f"git {' '.join(arguments)}: {completed.stderr.strip()}")

    def commit(self, name: str) -> None:
        pathlib.Path(name).write_text(name)
        self.run_git("add", name)
        self.run_git("commit", "--quiet", "-m", name)

    def test_diffs_a_root_commit_against_the_empty_tree(self) -> None:
        self.assertEqual(build_commit_range("HEAD"), (EMPTY_TREE_OBJECT, "HEAD"))

    def test_diffs_a_later_commit_against_its_parent(self) -> None:
        self.commit("second")
        self.assertEqual(build_commit_range("HEAD"), ("HEAD^", "HEAD"))


class ResolveExplicitRangeTest(unittest.TestCase):
    """resolve_explicit_range turns the scope flags into endpoints."""

    def resolve(self, **flags: object) -> tuple[str, str, str] | None:
        arguments: dict[str, object] = {"last": None, "commit": None, "range": None}
        arguments.update(flags)
        return resolve_explicit_range(argparse.Namespace(**arguments))

    def test_returns_none_when_no_scope_flag_is_set(self) -> None:
        self.assertIsNone(self.resolve())

    def test_reads_last_as_a_count_back_from_head(self) -> None:
        resolved = self.resolve(last=1)
        assert resolved is not None
        left, right, description = resolved
        self.assertEqual((left, right), ("HEAD~1", "HEAD"))
        self.assertIn("the most recent commit", description)

    def test_reads_commit_as_its_own_change(self) -> None:
        with mock.patch.object(
            gather_review_context, "build_commit_range", return_value=("abc123^", "abc123")
        ) as build_commit_range_mock:
            resolved = self.resolve(commit="abc123")
        build_commit_range_mock.assert_called_once_with("abc123")
        assert resolved is not None
        self.assertEqual(resolved[:2], ("abc123^", "abc123"))

    def test_passes_a_two_dot_range_through_untouched(self) -> None:
        resolved = self.resolve(range="abc123..def456")
        self.assertEqual(resolved, ("abc123", "def456", "--range abc123..def456"))

    def test_replaces_a_three_dot_left_endpoint_with_the_merge_base(self) -> None:
        with mock.patch.object(
            gather_review_context, "find_merge_base", return_value="mergebase"
        ):
            resolved = self.resolve(range="main...HEAD")
        assert resolved is not None
        left, right, description = resolved
        self.assertEqual((left, right), ("mergebase", "HEAD"))
        self.assertIn("since the two diverged", description)


if __name__ == "__main__":
    unittest.main()
