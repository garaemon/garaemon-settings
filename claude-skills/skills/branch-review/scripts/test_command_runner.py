"""Tests for the shared command runner, including absent executables.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import pathlib
import tempfile
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


class RunCommandOnAnUnusableExecutableTest(unittest.TestCase):
    """run_command reports a command it cannot execute instead of crashing."""

    def build_unusable_command(self, directory: str) -> str:
        """Return the path of a file that exists but carries no execute bit."""
        command_path = pathlib.Path(directory) / "gh"
        command_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        command_path.chmod(0o600)
        return str(command_path)

    def test_should_return_empty_for_an_unusable_command_when_check_is_false(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            command = self.build_unusable_command(directory)
            self.assertEqual(run_command([command], check=False), "")

    def test_should_raise_a_runtime_error_for_an_unusable_command(self) -> None:
        # PermissionError is an OSError like FileNotFoundError, and the callers
        # catch RuntimeError and ValueError only.
        with tempfile.TemporaryDirectory() as directory:
            command = self.build_unusable_command(directory)
            with self.assertRaises(RuntimeError):
                run_command([command])

    def test_should_name_the_unusable_command_in_the_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            command = self.build_unusable_command(directory)
            with self.assertRaisesRegex(RuntimeError, "cannot be run"):
                run_command([command])


class RunGhCommandTest(unittest.TestCase):
    """run_gh_command degrades the same way when the gh CLI is absent."""

    def test_should_return_empty_for_an_absent_gh_when_check_is_false(self) -> None:
        # Claude Code on the web ships no gh; an optional lookup there must
        # fall through to "no pull request" rather than end the review.
        self.assertEqual(run_gh_command([MISSING_COMMAND, "api"], check=False), "")


if __name__ == "__main__":
    unittest.main()
