"""Tests for git-commit-llm."""

import importlib.util
import os
import sys
from unittest.mock import patch

import pytest

# Load the script as a module (it has no .py extension)
_script_path = os.path.join(
    os.path.dirname(__file__),
    "..",
    "dot_local",
    "bin",
    "executable_git-commit-llm",
)
_script_path = os.path.abspath(_script_path)
_loader = importlib.machinery.SourceFileLoader("git_commit_llm", _script_path)
_spec = importlib.util.spec_from_loader("git_commit_llm", _loader)
gcl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gcl)


# ---------------------------------------------------------------------------
# format_commit_message
# ---------------------------------------------------------------------------
class TestFormatCommitMessage:
    def test_basic_json(self):
        raw = '{"summary": "Add user auth", "details": ["Add login endpoint", "Add JWT validation"]}'
        result = gcl.format_commit_message(raw)
        assert result == "Add user auth\n\n- Add login endpoint\n- Add JWT validation"

    def test_summary_only(self):
        raw = '{"summary": "Fix typo", "details": []}'
        result = gcl.format_commit_message(raw)
        assert result == "Fix typo"

    def test_no_details_key(self):
        raw = '{"summary": "Fix typo"}'
        result = gcl.format_commit_message(raw)
        assert result == "Fix typo"

    def test_strips_whitespace_from_summary(self):
        raw = '{"summary": "  Add feature  ", "details": ["Detail"]}'
        result = gcl.format_commit_message(raw)
        assert result.startswith("Add feature")

    def test_strips_whitespace_from_details(self):
        raw = '{"summary": "Fix bug", "details": ["  Fix null check  ", "  Add test  "]}'
        result = gcl.format_commit_message(raw)
        assert "- Fix null check" in result
        assert "- Add test" in result

    def test_skips_empty_details(self):
        raw = '{"summary": "Fix bug", "details": ["Valid", "", "  ", "Also valid"]}'
        result = gcl.format_commit_message(raw)
        lines = result.split("\n")
        bullet_lines = [l for l in lines if l.startswith("- ")]
        assert len(bullet_lines) == 2
        assert "- Valid" in bullet_lines
        assert "- Also valid" in bullet_lines

    def test_strips_markdown_code_fences(self):
        raw = '```json\n{"summary": "Add feature", "details": ["Change A"]}\n```'
        result = gcl.format_commit_message(raw)
        assert result == "Add feature\n\n- Change A"

    def test_strips_code_fence_without_language(self):
        raw = '```\n{"summary": "Add feature", "details": ["Change A"]}\n```'
        result = gcl.format_commit_message(raw)
        assert result == "Add feature\n\n- Change A"

    def test_fallback_on_invalid_json(self):
        raw = "This is not JSON at all"
        result = gcl.format_commit_message(raw)
        assert result == "This is not JSON at all"

    def test_fallback_on_empty_summary(self):
        raw = '{"summary": "", "details": ["Detail"]}'
        result = gcl.format_commit_message(raw)
        assert result == raw.strip()

    def test_fallback_on_missing_summary(self):
        raw = '{"details": ["Detail"]}'
        result = gcl.format_commit_message(raw)
        assert result == raw.strip()

    def test_multiline_json(self):
        raw = """{
  "summary": "Refactor config",
  "details": [
    "Extract config parsing into separate module",
    "Add validation for required fields"
  ]
}"""
        result = gcl.format_commit_message(raw)
        assert result == (
            "Refactor config\n\n"
            "- Extract config parsing into separate module\n"
            "- Add validation for required fields"
        )

    def test_non_string_details_ignored(self):
        raw = '{"summary": "Fix bug", "details": ["Valid", 123, null, "Also valid"]}'
        result = gcl.format_commit_message(raw)
        lines = result.split("\n")
        bullet_lines = [l for l in lines if l.startswith("- ")]
        assert len(bullet_lines) == 2

    def test_details_not_a_list(self):
        raw = '{"summary": "Fix bug", "details": "not a list"}'
        result = gcl.format_commit_message(raw)
        assert result == "Fix bug"

    def test_summary_with_newlines(self):
        raw = '{"summary": "Add feature\\nwith extra line", "details": ["Detail"]}'
        result = gcl.format_commit_message(raw)
        summary_line = result.split("\n\n")[0]
        assert "\n" not in summary_line


# ---------------------------------------------------------------------------
# build_system_prompt
# ---------------------------------------------------------------------------
class TestBuildSystemPrompt:
    def test_without_feedback(self):
        prompt = gcl.build_system_prompt()
        assert prompt == gcl.BASE_SYSTEM_PROMPT

    def test_with_feedback(self):
        prompt = gcl.build_system_prompt("write in Japanese")
        assert gcl.BASE_SYSTEM_PROMPT in prompt
        assert "write in Japanese" in prompt
        assert "Additional instructions from the user:" in prompt


# ---------------------------------------------------------------------------
# build_feedback_prompt
# ---------------------------------------------------------------------------
class TestBuildFeedbackPrompt:
    def test_includes_current_message(self):
        prompt = gcl.build_feedback_prompt("Add feature\n\n- Detail", "be more concise")
        assert "Add feature" in prompt
        assert "be more concise" in prompt
        assert "previously generated" in prompt


# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------
class TestParseArgs:
    def test_defaults(self):
        args = gcl.parse_args([])
        assert args.model == gcl.DEFAULT_MODEL
        assert args.feedback == ""
        assert args.model_positional is None

    def test_model_flag(self):
        args = gcl.parse_args(["-m", "gpt-4o"])
        assert args.model == "gpt-4o"

    def test_feedback_flag(self):
        args = gcl.parse_args(["-f", "write in Japanese"])
        assert args.feedback == "write in Japanese"

    def test_positional_model(self):
        args = gcl.parse_args(["gpt-4o"])
        assert args.model_positional == "gpt-4o"

    def test_positional_overrides_default(self):
        """Positional model should be used when -m is not specified."""
        args = gcl.parse_args(["gpt-4o"])
        model = args.model_positional or args.model
        assert model == "gpt-4o"

    def test_flag_model_when_no_positional(self):
        args = gcl.parse_args(["-m", "claude-sonnet"])
        model = args.model_positional or args.model
        assert model == "claude-sonnet"

    def test_combined_options(self):
        args = gcl.parse_args(["-m", "gpt-4o", "-f", "be concise"])
        assert args.model == "gpt-4o"
        assert args.feedback == "be concise"
