"""Tests for the Claude Code worklog hook that appends to the org-roam daily note."""

import importlib.machinery
import importlib.util
import json
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

SCRIPT_PATH = (
    Path(__file__).resolve().parent.parent
    / "dot_claude"
    / "hooks"
    / "executable_claude_worklog.py"
)
_loader = importlib.machinery.SourceFileLoader("claude_worklog", str(SCRIPT_PATH))
_spec = importlib.util.spec_from_loader("claude_worklog", _loader)
worklog = importlib.util.module_from_spec(_spec)
# The hook lives in the chezmoi source tree, where a __pycache__ directory
# would be installed into ~/.claude/hooks as a managed file.
sys.dont_write_bytecode = True
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
        "user_prompts": ("Fix the login bug",),
        "assistant_texts": ("Fixed it.",),
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
    lines = [make_user_line("<command-name>/clear</command-name>", "2026-10-31T10:00:00Z", isMeta=True)]

    digest = parse_lines(lines)

    assert digest.user_prompts == ()


def test_should_keep_only_text_blocks_when_collecting_assistant_texts():
    lines = [make_assistant_line("Done.", "2026-10-31T10:01:00Z")]

    digest = parse_lines(lines)

    assert digest.assistant_texts == ("Done.",)


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

    assert [(i.start.hour, i.end.hour) for i in intervals] == [(9, 9), (13, 13)]


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
    digest = make_digest(user_prompts=("Fix the login bug\nwith details",))

    summary = worklog.build_fallback_summary(digest)

    assert summary.title == "Fix the login bug"


def test_should_render_entry_with_active_timestamp_and_tags():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert entry.splitlines()[0] == "* <2026-10-31 Sat 14:02> project: Fix login :claude:worklog:"


def test_should_render_entry_with_session_id_property():
    digest = make_digest()
    summary = worklog.Summary(title="Fix login", bullets=("Patch auth",))

    entry = worklog.render_entry(digest, summary, timedelta(minutes=30))

    assert ":SESSION_ID: session-1" in entry


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


def test_should_skip_hook_when_recursion_guard_is_set():
    environment = {worklog.RECURSION_GUARD_ENV: "1", "ORG_DIR": "/tmp/org"}

    should_run = worklog.should_log_session(environment, Path("/nonexistent"))

    assert should_run is False


def test_should_skip_hook_when_roam_directory_is_missing(tmp_path):
    should_run = worklog.should_log_session({}, tmp_path / "missing")

    assert should_run is False


def test_should_run_hook_when_roam_directory_exists(tmp_path):
    should_run = worklog.should_log_session({}, tmp_path)

    assert should_run is True


def test_should_resolve_daily_directory_from_org_dir_env():
    daily_dir = worklog.resolve_daily_directory({"ORG_DIR": "/data/org"}, Path("/home/me"))

    assert daily_dir == Path("/data/org/org-roam/daily")


def test_should_resolve_daily_directory_from_default_when_env_is_unset():
    daily_dir = worklog.resolve_daily_directory({}, Path("/home/me"))

    assert daily_dir == Path("/home/me/ghq/github.com/garaemon/org/org-roam/daily")
