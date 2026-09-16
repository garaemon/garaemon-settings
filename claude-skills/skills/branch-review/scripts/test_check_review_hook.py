"""Tests for the PostToolUse hook that checks review.json after it is written.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from typing import Any

import check_review_hook
from test_render_review import build_review, write_checkout


def build_payload(file_path: str, tool_name: str = "Write") -> dict[str, Any]:
    """Return the JSON Claude Code sends a PostToolUse hook on stdin."""
    return {
        "hook_event_name": "PostToolUse",
        "tool_name": tool_name,
        "tool_input": {"file_path": file_path},
    }


def run_hook(payload: dict[str, Any], root: str) -> tuple[int, str]:
    """Run the hook on the payload and return (exit status, stderr text)."""
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr):
        status = check_review_hook.check_written_review(json.dumps(payload), pathlib.Path(root))
    return status, stderr.getvalue()


class SelectReviewPathTest(unittest.TestCase):
    """select_review_path picks out writes to a review.json file."""

    def test_returns_the_path_of_a_review_file(self) -> None:
        payload = build_payload("/tmp/scratch/review.json")
        self.assertEqual(
            check_review_hook.select_review_path(payload), pathlib.Path("/tmp/scratch/review.json")
        )

    def test_ignores_other_files(self) -> None:
        self.assertIsNone(check_review_hook.select_review_path(build_payload("/tmp/notes.md")))

    def test_ignores_a_payload_without_a_file_path(self) -> None:
        self.assertIsNone(check_review_hook.select_review_path({"tool_input": {}}))


class CheckWrittenReviewTest(unittest.TestCase):
    """check_written_review exits 0 for clean input and 2 with the problems for a bad review."""

    def test_passes_a_file_that_is_not_a_review(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status, stderr = run_hook(build_payload(f"{directory}/notes.md"), directory)
            self.assertEqual((status, stderr), (0, ""))

    def test_passes_a_clean_review(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, {"src/main/index.ts": "x\n" * 40})
            review_path = root / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            status, stderr = run_hook(build_payload(str(review_path)), directory)
            self.assertEqual((status, stderr), (0, ""))

    def test_ignores_a_review_json_that_is_not_a_review(self) -> None:
        # A project under review may keep its own review.json; a file without
        # a "categories" key is not this skill's and must not halt the session.
        with tempfile.TemporaryDirectory() as directory:
            review_path = pathlib.Path(directory) / "review.json"
            review_path.write_text(json.dumps({"reviewers": ["octocat"]}), encoding="utf-8")
            status, stderr = run_hook(build_payload(str(review_path)), directory)
            self.assertEqual((status, stderr), (0, ""))

    def test_reports_check_failures_with_exit_status_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, {})
            review_path = root / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            status, stderr = run_hook(build_payload(str(review_path)), directory)
            self.assertEqual(status, 2)
            self.assertIn("src/main/index.ts", stderr)

    def test_reports_malformed_json_with_exit_status_two(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            review_path = pathlib.Path(directory) / "review.json"
            review_path.write_text("{", encoding="utf-8")
            status, stderr = run_hook(build_payload(str(review_path)), directory)
            self.assertEqual(status, 2)
            self.assertIn("review.json", stderr)

    def test_passes_when_the_hook_payload_is_not_json(self) -> None:
        # A hook that fails on its own input would block every write, so
        # unreadable input is treated as "nothing to check".
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = check_review_hook.check_written_review("not json", pathlib.Path("/tmp"))
        self.assertEqual(status, 0)


if __name__ == "__main__":
    unittest.main()
