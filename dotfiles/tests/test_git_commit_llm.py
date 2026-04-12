"""Tests for git-commit-llm."""

import importlib.util
import importlib.machinery
import json
import os
import sys
from unittest.mock import patch, MagicMock

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

    def test_strips_bullet_prefix_from_details(self):
        raw = '{"summary": "Fix bug", "details": ["- Already bulleted", "* Star bulleted", "No prefix"]}'
        result = gcl.format_commit_message(raw)
        assert "- Already bulleted" in result
        assert "- Star bulleted" in result
        assert "- No prefix" in result
        # Should not have double bullets
        assert "- - " not in result
        assert "- * " not in result

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


# ---------------------------------------------------------------------------
# call_llm (Ollama API)
# ---------------------------------------------------------------------------
class TestCallLlm:
    def test_sends_correct_request(self):
        """Verify the request payload sent to Ollama chat API."""
        response_body = json.dumps(
            {"message": {"content": '{"summary": "Test"}'}}
        ).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = response_body
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_urlopen:
            result = gcl.call_llm("diff content", "system prompt", "gemma3:4b")

            # Verify the response
            assert result == '{"summary": "Test"}'

            # Verify the request uses chat API with messages
            call_args = mock_urlopen.call_args[0][0]
            payload = json.loads(call_args.data.decode("utf-8"))
            assert payload["model"] == "gemma3:4b"
            assert payload["stream"] is False
            assert payload["format"] == "json"
            # Should use messages format with system and user roles
            messages = payload["messages"]
            assert len(messages) == 2
            assert messages[0]["role"] == "system"
            assert messages[0]["content"] == "system prompt"
            assert messages[1]["role"] == "user"
            assert "<diff>" in messages[1]["content"]
            assert "diff content" in messages[1]["content"]
            assert "</diff>" in messages[1]["content"]

    def test_uses_ollama_host_env(self):
        """Verify OLLAMA_HOST env var is respected."""
        response_body = json.dumps(
            {"message": {"content": "test"}}
        ).encode()
        mock_resp = MagicMock()
        mock_resp.read.return_value = response_body
        mock_resp.__enter__ = lambda s: s
        mock_resp.__exit__ = MagicMock(return_value=False)

        with patch("urllib.request.urlopen", return_value=mock_resp) as mock_urlopen:
            with patch.dict(os.environ, {"OLLAMA_HOST": "http://myhost:1234"}):
                gcl.call_llm("diff", "prompt", "model")

                call_args = mock_urlopen.call_args[0][0]
                assert call_args.full_url == "http://myhost:1234/api/chat"

    def test_default_ollama_host(self):
        assert gcl.DEFAULT_OLLAMA_HOST == "http://localhost:11434"

    def test_connection_error_exits(self):
        """Verify sys.exit on connection failure."""
        import urllib.error

        with patch(
            "urllib.request.urlopen",
            side_effect=urllib.error.URLError("Connection refused"),
        ):
            with pytest.raises(SystemExit):
                gcl.call_llm("diff", "prompt", "model")


# ---------------------------------------------------------------------------
# compact_diff
# ---------------------------------------------------------------------------
class TestCompactDiff:
    def test_keeps_diff_headers(self):
        diff = "diff --git a/foo.py b/foo.py\nindex abc..def 100644\n--- a/foo.py\n+++ b/foo.py"
        result = gcl.compact_diff(diff)
        assert "diff --git a/foo.py b/foo.py" in result
        assert "index abc..def 100644" in result
        assert "--- a/foo.py" in result
        assert "+++ b/foo.py" in result

    def test_keeps_hunk_headers(self):
        diff = "@@ -1,3 +1,4 @@\n context line\n+added line\n-removed line"
        result = gcl.compact_diff(diff)
        assert "@@ -1,3 +1,4 @@" in result

    def test_keeps_added_removed_lines(self):
        diff = "@@ -1,3 +1,4 @@\n context\n+added\n-removed\n another context"
        result = gcl.compact_diff(diff)
        assert "+added" in result
        assert "-removed" in result

    def test_strips_context_lines(self):
        diff = "@@ -1,3 +1,4 @@\n context line\n+added\n more context"
        result = gcl.compact_diff(diff)
        assert "context line" not in result
        assert "more context" not in result

    def test_realistic_diff(self):
        diff = (
            "diff --git a/README.md b/README.md\n"
            "index abc..def 100644\n"
            "--- a/README.md\n"
            "+++ b/README.md\n"
            "@@ -1,5 +1,5 @@\n"
            " # My Project\n"
            " \n"
            "-Old description\n"
            "+New description\n"
            " \n"
            " ## Installation\n"
        )
        result = gcl.compact_diff(diff)
        # Context lines should be stripped
        assert "# My Project" not in result
        assert "## Installation" not in result
        # Changed lines should remain
        assert "-Old description" in result
        assert "+New description" in result

    def test_empty_diff(self):
        assert gcl.compact_diff("") == ""
