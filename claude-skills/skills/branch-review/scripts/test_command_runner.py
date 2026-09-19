"""Tests for the shared command runner, including absent executables.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import unittest

from commands import run_command, run_gh_command

MISSING_COMMAND = "branch-review-no-such-command"


class RunCommandTest(unittest.TestCase):
    """run_command returns stdout, and reports a failure the caller can act on."""

    def test_should_return_stdout_of_a_command_that_succeeds(self) -> None:
        self.assertEqual(run_command(["echo", "hello"]).strip(), "hello")

    def test_should_return_empty_for_a_failing_command_when_check_is_false(self) -> None:
        self.assertEqual(run_command(["false"], check=False), "")

    def test_should_raise_naming_a_failing_command_when_check_is_true(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "false"):
            run_command(["false"])

    def test_should_return_empty_for_an_absent_command_when_check_is_false(self) -> None:
        self.assertEqual(run_command([MISSING_COMMAND], check=False), "")

    def test_should_raise_a_runtime_error_for_an_absent_command(self) -> None:
        # A bare FileNotFoundError escapes the callers, which catch RuntimeError
        # and ValueError only, and ends the review in a traceback.
        with self.assertRaises(RuntimeError):
            run_command([MISSING_COMMAND])

    def test_should_name_the_absent_command_in_the_error(self) -> None:
        with self.assertRaisesRegex(RuntimeError, MISSING_COMMAND):
            run_command([MISSING_COMMAND])

    def test_should_say_the_absent_command_is_not_installed(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "not installed"):
            run_command([MISSING_COMMAND])


class RunGhCommandTest(unittest.TestCase):
    """run_gh_command degrades the same way when the gh CLI is absent."""

    def test_should_return_empty_for_an_absent_gh_when_check_is_false(self) -> None:
        # Claude Code on the web ships no gh; an optional lookup there must
        # fall through to "no pull request" rather than end the review.
        self.assertEqual(run_gh_command([MISSING_COMMAND, "api"], check=False), "")


if __name__ == "__main__":
    unittest.main()
