"""Tests for the Claude Code worklog hook that appends to the org-roam daily note."""

import importlib.machinery
import importlib.util
import json
import subprocess
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pytest

SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent
    / "dot_claude"
    / "hooks"
    / "executable_claude_worklog.py"
)
_loader = importlib.machinery.SourceFileLoader("claude_worklog", str(SCRIPT_PATH))
_spec = importlib.util.spec_from_loader("claude_worklog", _loader)
worklog = importlib.util.module_from_spec(_spec)
# dataclasses resolves the postponed annotations of the hook through
# sys.modules, so the module must be registered before it runs.
sys.modules["claude_worklog"] = worklog
_spec.loader.exec_module(worklog)

UTC = timezone.utc
TARGET_DAY = date(2026, 10, 31)


def make_user_line(text, timestamp, **extra):
    record = {
        "type": "user",
        "timestamp": timestamp,
        "sessionId": "session-1",
        "cwd": "/home/me/ghq/github.com/me/project",
        "gitBranch": "feature-x",
        "isSidechain": False,
        "message": {"role": "user", "content": text},
    }
    record.update(extra)
    return json.dumps(record)


def make_assistant_line(text, timestamp):
    return json.dumps(
        {
            "type": "assistant",
            "timestamp": timestamp,
            "sessionId": "session-1",
            "isSidechain": False,
            "message": {
                "role": "assistant",
                "content": [
                    {"type": "thinking", "thinking": "secret thoughts"},
                    {"type": "text", "text": text},
                ],
            },
        }
    )


def make_tool_result_line(timestamp):
    return json.dumps(
        {
            "type": "user",
            "timestamp": timestamp,
            "sessionId": "session-1",
            "isSidechain": False,
            "message": {
                "role": "user",
                "content": [{"type": "tool_result", "content": "huge output"}],
            },
        }
    )


def parse_lines(lines):
    return worklog.parse_transcript(lines, TARGET_DAY, UTC)


def make_digest(**overrides):
    fields = {
        "session_id": "session-1",
        "cwd": "/home/me/ghq/github.com/me/project",
        "branch": "feature-x",
        "timestamps": (
            datetime(2026, 10, 31, 14, 2, tzinfo=UTC),
            datetime(2026, 10, 31, 14, 25, tzinfo=UTC),
            datetime(2026, 10, 31, 14, 47, tzinfo=UTC),
        ),
        "turns": (
            worklog.Turn(role="USER", text="Fix the login bug"),
            worklog.Turn(role="ASSISTANT", text="Fixed it."),
        ),
    }
    fields.update(overrides)
    return worklog.SessionDigest(**fields)


def test_should_collect_user_prompts_when_content_is_string():
    lines = [make_user_line("Fix the bug", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("Fix the bug",)


def test_should_skip_tool_results_when_collecting_prompts():
    lines = [
        make_user_line("Fix the bug", "2026-10-31T10:00:00Z"),
        make_tool_result_line("2026-10-31T10:00:05Z"),
    ]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("Fix the bug",)


def test_should_skip_meta_messages_when_collecting_prompts():
    lines = [make_user_line("Caveat: the messages below were generated", "2026-10-31T10:00:00Z", isMeta=True)]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


def test_should_keep_only_text_blocks_when_collecting_assistant_turns():
    lines = [make_assistant_line("Done.", "2026-10-31T10:01:00Z")]

    digest = parse_lines(lines)

    assert digest.turns == (worklog.Turn(role="ASSISTANT", text="Done."),)


def test_should_keep_turns_in_transcript_order():
    lines = [
        make_user_line("First ask", "2026-10-31T10:00:00Z"),
        make_assistant_line("First answer", "2026-10-31T10:01:00Z"),
        make_user_line("Second ask", "2026-10-31T10:02:00Z"),
    ]

    digest = parse_lines(lines)

    assert [turn.text for turn in digest.turns] == ["First ask", "First answer", "Second ask"]


def test_should_interleave_turns_in_summary_input():
    digest = make_digest(
        turns=(
            worklog.Turn(role="USER", text="First ask"),
            worklog.Turn(role="ASSISTANT", text="First answer"),
            worklog.Turn(role="USER", text="Second ask"),
        )
    )

    summary_input = worklog.build_summary_input(digest)

    assert "USER: First ask\n\nASSISTANT: First answer\n\nUSER: Second ask" in summary_input


def test_should_keep_first_prompt_when_summary_input_is_trimmed():
    long_answer = "x" * (worklog.MAX_TRANSCRIPT_CHARS_FOR_SUMMARY * 2)
    digest = make_digest(
        turns=(
            worklog.Turn(role="USER", text="Original ask"),
            worklog.Turn(role="ASSISTANT", text=long_answer),
            worklog.Turn(role="ASSISTANT", text="Final answer"),
        )
    )

    summary_input = worklog.build_summary_input(digest)

    assert "USER: Original ask" in summary_input


def test_should_keep_last_turn_when_summary_input_is_trimmed():
    long_answer = "x" * (worklog.MAX_TRANSCRIPT_CHARS_FOR_SUMMARY * 2)
    digest = make_digest(
        turns=(
            worklog.Turn(role="USER", text="Original ask"),
            worklog.Turn(role="ASSISTANT", text=long_answer),
            worklog.Turn(role="ASSISTANT", text="Final answer"),
        )
    )

    summary_input = worklog.build_summary_input(digest)

    assert summary_input.rstrip().endswith("ASSISTANT: Final answer\n</transcript>")


def test_should_bound_summary_input_when_first_prompt_is_huge():
    huge_prompt = "y" * (worklog.MAX_TRANSCRIPT_CHARS_FOR_SUMMARY * 2)
    digest = make_digest(turns=(worklog.Turn(role="USER", text=huge_prompt),))

    summary_input = worklog.build_summary_input(digest)

    assert len(summary_input) < worklog.MAX_TRANSCRIPT_CHARS_FOR_SUMMARY + len(worklog.SUMMARY_INSTRUCTIONS) + 100


def test_should_drop_events_from_other_days():
    lines = [
        make_user_line("Yesterday task", "2026-10-30T23:00:00Z"),
        make_user_line("Today task", "2026-10-31T09:00:00Z"),
    ]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("Today task",)


def test_should_record_cwd_and_branch_from_transcript():
    lines = [make_user_line("Fix the bug", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert (digest.cwd, digest.branch) == ("/home/me/ghq/github.com/me/project", "feature-x")


def test_should_ignore_malformed_lines():
    lines = ["not json", make_user_line("Fix the bug", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("Fix the bug",)


def test_should_split_clock_intervals_when_gap_exceeds_limit():
    timestamps = (
        datetime(2026, 10, 31, 9, 0, tzinfo=UTC),
        datetime(2026, 10, 31, 9, 20, tzinfo=UTC),
        datetime(2026, 10, 31, 13, 0, tzinfo=UTC),
        datetime(2026, 10, 31, 13, 10, tzinfo=UTC),
    )

    intervals = worklog.compute_clock_intervals(timestamps, timedelta(minutes=30))

    assert [(interval.start.hour, interval.end.hour) for interval in intervals] == [(9, 9), (13, 13)]


def test_should_drop_interval_when_it_lasts_under_a_minute():
    timestamps = (
        datetime(2026, 10, 31, 9, 0, tzinfo=UTC),
        datetime(2026, 10, 31, 13, 0, 30, tzinfo=UTC),
    )

    intervals = worklog.compute_clock_intervals(timestamps, timedelta(minutes=30))

    assert intervals == ()


def test_should_return_no_interval_when_timestamps_are_empty():
    intervals = worklog.compute_clock_intervals((), timedelta(minutes=30))

    assert intervals == ()


def test_should_format_clock_line_in_org_syntax():
    interval = worklog.ClockInterval(
        start=datetime(2026, 10, 31, 14, 2, tzinfo=UTC),
        end=datetime(2026, 10, 31, 15, 47, tzinfo=UTC),
    )

    line = worklog.format_clock_line(interval)

    assert line == "CLOCK: [2026-10-31 Sat 14:02]--[2026-10-31 Sat 15:47] =>  1:45"


def test_should_parse_summary_json_from_model_output():
    response = '```json\n{"title": "Fix login", "bullets": ["Patch auth", "Add test"]}\n```'

    summary = worklog.parse_summary_response(response)

    assert summary == worklog.Summary(title="Fix login", bullets=("Patch auth", "Add test"))


def test_should_return_none_when_summary_is_not_json():
    summary = worklog.parse_summary_response("Sorry, I cannot do that.")

    assert summary is None


def test_should_fall_back_to_first_prompt_when_summary_fails():
    digest = make_digest(turns=(worklog.Turn(role="USER", text="Fix the login bug\nwith details"),))

    summary = worklog.build_fallback_summary(digest)

    assert summary.title == "Fix the login bug"


def test_should_render_entry_with_active_timestamp_and_tags():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert entry.splitlines()[0] == "* <2026-10-31 Sat 14:02> project: Fix login :claude:autogenerated:worklog:"


def test_should_render_entry_with_session_id_property():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert ":SESSION_ID: session-1" in entry


def test_should_render_entry_with_host_property():
    digest = make_digest(hostname="workstation")
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert ":HOST: workstation" in entry


def test_should_drop_domain_when_shortening_hostname():
    short_hostname = worklog.shorten_hostname("macbook.local")

    assert short_hostname == "macbook"


def test_should_keep_hostname_when_it_has_no_domain():
    short_hostname = worklog.shorten_hostname("workstation")

    assert short_hostname == "workstation"


def test_should_render_entry_with_clock_in_logbook():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert ":LOGBOOK:\nCLOCK: [2026-10-31 Sat 14:02]--[2026-10-31 Sat 14:47] =>  0:45\n:END:" in entry


def test_should_render_bullets_after_drawers():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth", "Add test"))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert entry.endswith("- Patch auth\n- Add test\n")


def test_should_append_entry_when_session_is_new():
    existing = "#+title: 2026-10-31\n* <2026-10-31 Sat 09:00> memo\n"
    entry = "* new entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n"

    updated = worklog.upsert_entry(existing, "session-1", entry)

    assert updated == existing + entry


def test_should_replace_entry_when_session_already_logged():
    existing = (
        "#+title: 2026-10-31\n"
        "* old entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n- old\n"
        "* <2026-10-31 Sat 12:00> lunch memo\n"
    )
    entry = "* new entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n- new\n"

    updated = worklog.upsert_entry(existing, "session-1", entry)

    assert updated == (
        "#+title: 2026-10-31\n"
        + entry
        + "* <2026-10-31 Sat 12:00> lunch memo\n"
    )


def test_should_add_newline_before_entry_when_file_lacks_trailing_newline():
    existing = "#+title: 2026-10-31"
    entry = "* new entry\n"

    updated = worklog.upsert_entry(existing, "session-1", entry)

    assert updated == "#+title: 2026-10-31\n* new entry\n"


def test_should_create_daily_file_with_roam_header(tmp_path):
    daily_file = tmp_path / "daily" / "2026-10-31.org"

    worklog.write_daily_note(daily_file, TARGET_DAY, "session-1", "* entry\n")

    assert daily_file.read_text().startswith(":PROPERTIES:\n:ID:       ")


def test_should_keep_existing_content_when_writing_daily_file(tmp_path):
    daily_file = tmp_path / "2026-10-31.org"
    daily_file.write_text("#+title: 2026-10-31\n* memo\n")

    worklog.write_daily_note(daily_file, TARGET_DAY, "session-1", "* entry\n")

    assert daily_file.read_text() == "#+title: 2026-10-31\n* memo\n* entry\n"


def test_should_skip_hook_when_recursion_guard_is_set(tmp_path):
    environment = {worklog.RECURSION_GUARD_ENV: "1"}

    should_run = worklog.should_log_session(environment, tmp_path)

    assert should_run is False


def test_should_skip_hook_when_roam_directory_is_missing(tmp_path):
    should_run = worklog.should_log_session({}, tmp_path / "missing")

    assert should_run is False


def test_should_run_hook_when_roam_directory_exists(tmp_path):
    should_run = worklog.should_log_session({}, tmp_path)

    assert should_run is True


def test_should_resolve_daily_directory_from_org_dir_env():
    daily_directory = worklog.resolve_daily_directory({"ORG_DIR": "/data/org"}, Path("/home/me"))

    assert daily_directory == Path("/data/org/org-roam/daily")


def test_should_resolve_daily_directory_from_default_when_env_is_unset():
    daily_directory = worklog.resolve_daily_directory({}, Path("/home/me"))

    assert daily_directory == Path("/home/me/ghq/github.com/garaemon/org/org-roam/daily")


def test_should_keep_parent_heading_when_entry_was_demoted():
    existing = "* Work\n** old entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n- old\n** other\n"
    entry = "* new entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n"

    updated = worklog.upsert_entry(existing, "session-1", entry)

    assert updated == "* Work\n** new entry\n:PROPERTIES:\n:SESSION_ID: session-1\n:END:\n** other\n"


def test_should_append_entry_when_session_id_has_no_heading():
    existing = ":PROPERTIES:\n:SESSION_ID: session-1\n:END:\n"

    updated = worklog.upsert_entry(existing, "session-1", "* new entry\n")

    assert updated == existing + "* new entry\n"


def test_should_collect_user_prompt_when_content_is_block_list():
    content = [{"type": "image", "source": {}}, {"type": "text", "text": "Fix the bug"}]
    lines = [make_user_line("", "2026-10-31T10:00:00Z", message={"role": "user", "content": content})]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("Fix the bug",)


def capture_summarizer_call(monkeypatch):
    captured_calls = []

    def fake_run(command, *, env, **_kwargs):
        captured_calls.append({"command": command, "env": env})
        return subprocess.CompletedProcess(args=command, returncode=0, stdout="", stderr="")

    monkeypatch.setattr(worklog.subprocess, "run", fake_run)
    worklog.summarize_session(make_digest())
    return captured_calls[0]


def test_should_strip_claudecode_when_summarizing(monkeypatch):
    monkeypatch.setenv("CLAUDECODE", "1")

    summarizer_call = capture_summarizer_call(monkeypatch)

    assert "CLAUDECODE" not in summarizer_call["env"]


def test_should_set_recursion_guard_when_summarizing(monkeypatch):
    summarizer_call = capture_summarizer_call(monkeypatch)

    assert summarizer_call["env"][worklog.RECURSION_GUARD_ENV] == "1"


def test_should_disable_tools_and_mcp_when_summarizing(monkeypatch):
    summarizer_call = capture_summarizer_call(monkeypatch)

    assert summarizer_call["command"][-3:] == ["--tools", "", "--strict-mcp-config"]


def test_should_use_command_name_when_prompt_is_slash_command():
    command_text = "<command-message>branch-review</command-message>\n<command-name>/branch-review</command-name>"
    lines = [make_user_line(command_text, "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("/branch-review",)


def test_should_skip_local_command_output_when_collecting_prompts():
    lines = [make_user_line("<local-command-stdout></local-command-stdout>", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


def test_should_skip_task_notification_when_collecting_prompts():
    lines = [make_user_line("<task-notification><task-id>1</task-id></task-notification>", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


def test_should_skip_clear_command_when_collecting_prompts():
    command_text = "<command-name>/clear</command-name>\n<command-message>clear</command-message>"
    lines = [make_user_line(command_text, "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


SYSTEM_PYTHON = Path("/usr/bin/python3")


@pytest.mark.skipif(not SYSTEM_PYTHON.exists(), reason="no system Python to check")
def test_should_import_hook_with_system_python():
    # macOS ships Python 3.9 as /usr/bin/python3, which the hook runs under
    # when Claude Code starts without mise on PATH.
    import_script = (
        "import importlib.machinery, importlib.util, sys;"
        "loader = importlib.machinery.SourceFileLoader('worklog', sys.argv[1]);"
        "spec = importlib.util.spec_from_loader('worklog', loader);"
        "module = sys.modules['worklog'] = importlib.util.module_from_spec(spec);"
        "loader.exec_module(module)"
    )

    completed_process = subprocess.run(
        [str(SYSTEM_PYTHON), "-B", "-c", import_script, str(SCRIPT_PATH)],
        capture_output=True,
        text=True,
        check=False,
    )

    assert completed_process.returncode == 0, completed_process.stderr


def test_should_skip_compact_summary_when_collecting_prompts():
    lines = [make_user_line("This session is being continued", "2026-10-31T10:00:00Z", isCompactSummary=True)]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


def test_should_append_args_when_slash_command_has_args():
    command_text = (
        "<command-message>branch-review</command-message>\n<command-name>/branch-review</command-name>\n"
        "<command-args>last commit</command-args>"
    )
    lines = [make_user_line(command_text, "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("/branch-review last commit",)


def test_should_keep_bash_input_as_command_when_collecting_prompts():
    lines = [make_user_line("<bash-input>git status</bash-input>", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ("!git status",)


def test_should_skip_bash_output_when_collecting_prompts():
    lines = [make_user_line("<bash-stdout>secret</bash-stdout><bash-stderr></bash-stderr>", "2026-10-31T10:00:00Z")]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()
