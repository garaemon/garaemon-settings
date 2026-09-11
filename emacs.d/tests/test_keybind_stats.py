"""Tests for scripts/keybind_stats.py.

The script reads the JSON lines that my-keybind-stats.el writes, so every
test builds a small stats directory under tmp_path and checks the report
that comes out of it.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import keybind_stats  # noqa: E402


def write_lines(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def event(command, keys, count=1, mode="python-mode", mx=False, bound=None,
          ts="2026-09-11T10:05:00+0900"):
    return {"ts": ts, "command": command, "keys": keys, "mode": mode,
            "mx": mx, "bound": bound, "count": count}


def binding(keys, command, scope="global"):
    return {"ts": "2026-09-11T09:00:00+0900", "scope": scope, "keys": keys,
            "command": command}


def make_stats_dir(tmp_path, events=(), bindings=()):
    write_lines(tmp_path / "events-2026-09.jsonl", events)
    by_scope = {}
    for row in bindings:
        by_scope.setdefault(row["scope"], []).append(row)
    for scope, rows in by_scope.items():
        write_lines(tmp_path / "bindings" / f"{scope}.jsonl", rows)
    return tmp_path


def summarize_dir(directory, **kwargs):
    events = keybind_stats.load_events(directory, since=None)
    bindings = keybind_stats.load_bindings(directory)
    return keybind_stats.summarize(events, bindings, **kwargs)


# Loading


def test_parse_event_should_read_all_fields():
    row = keybind_stats.parse_event(json.dumps(
        event("forward-char", "C-f", count=3, mx=True, bound="C-f")))
    assert row.command == "forward-char"
    assert row.keys == "C-f"
    assert row.mode == "python-mode"
    assert row.mx is True
    assert row.bound == "C-f"
    assert row.count == 3
    assert row.ts == datetime.fromisoformat("2026-09-11T10:05:00+09:00")


def test_load_events_should_read_every_monthly_file(tmp_path):
    write_lines(tmp_path / "events-2026-08.jsonl", [event("a", "C-a")])
    write_lines(tmp_path / "events-2026-09.jsonl", [event("b", "C-b")])
    events = keybind_stats.load_events(tmp_path, since=None)
    assert sorted(e.command for e in events) == ["a", "b"]


def test_load_events_should_drop_rows_before_since(tmp_path):
    write_lines(tmp_path / "events-2026-09.jsonl", [
        event("old", "C-a", ts="2026-09-01T10:00:00+0900"),
        event("new", "C-b", ts="2026-09-10T10:00:00+0900"),
    ])
    since = datetime(2026, 9, 5, tzinfo=timezone.utc)
    events = keybind_stats.load_events(tmp_path, since=since)
    assert [e.command for e in events] == ["new"]


def test_load_events_should_return_empty_for_missing_directory(tmp_path):
    assert keybind_stats.load_events(tmp_path / "missing", since=None) == []


def test_load_bindings_should_group_by_scope(tmp_path):
    make_stats_dir(tmp_path, bindings=[
        binding("C-f", "forward-char"),
        binding("C-c C-c", "python-shell-send-buffer", scope="python-mode"),
    ])
    bindings = keybind_stats.load_bindings(tmp_path)
    assert bindings["global"] == [("C-f", "forward-char")]
    assert bindings["python-mode"] == [("C-c C-c", "python-shell-send-buffer")]


# Summary


def test_summarize_should_rank_commands_by_total_count(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("forward-char", "C-f", count=2),
        event("forward-char", "<right>", count=3),
        event("backward-char", "C-b", count=4),
    ])
    report = summarize_dir(tmp_path)
    assert [(c.command, c.count) for c in report.top_commands] == [
        ("forward-char", 5), ("backward-char", 4)]


def test_summarize_should_list_keys_per_command(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("forward-char", "C-f", count=2),
        event("forward-char", "<right>", count=3),
    ])
    report = summarize_dir(tmp_path)
    assert report.top_commands[0].keys == [("<right>", 3), ("C-f", 2)]


def test_summarize_should_honor_top_limit(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("a", "C-a"), event("b", "C-b"), event("c", "C-c")])
    report = summarize_dir(tmp_path, top=2)
    assert len(report.top_commands) == 2


def test_summarize_should_list_forgotten_bindings(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("goto-line", "M-x", count=4, mx=True, bound="M-g"),
        event("goto-line", "M-g", count=1),
    ])
    report = summarize_dir(tmp_path)
    assert report.forgotten_bindings == [("goto-line", "M-g", 4)]


def test_summarize_should_list_unbound_commands_run_via_m_x(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("magit-log-all", "M-x", count=5, mx=True),
        event("goto-line", "M-x", count=4, mx=True, bound="M-g"),
    ])
    report = summarize_dir(tmp_path)
    assert report.unbound_favorites == [("magit-log-all", 5)]


def test_summarize_should_flag_long_key_sequences(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("org-clock-in", "C-c C-x C-i", count=7),
        event("forward-char", "C-f", count=9),
    ])
    report = summarize_dir(tmp_path)
    assert report.long_sequences == [("C-c C-x C-i", "org-clock-in", 7)]


def test_summarize_should_list_unused_global_bindings(tmp_path):
    make_stats_dir(tmp_path,
                   events=[event("forward-char", "C-f")],
                   bindings=[binding("C-f", "forward-char"),
                             binding("C-b", "backward-char")])
    report = summarize_dir(tmp_path)
    assert report.unused_bindings["global"] == [("C-b", "backward-char")]


def test_summarize_should_treat_local_binding_as_used_only_in_its_mode(tmp_path):
    make_stats_dir(tmp_path,
                   events=[event("compile", "C-c C-c", mode="c-mode")],
                   bindings=[
                       binding("C-c C-c", "compile", scope="c-mode"),
                       binding("C-c C-c", "send", scope="python-mode"),
                   ])
    report = summarize_dir(tmp_path)
    assert report.unused_bindings["c-mode"] == []
    assert report.unused_bindings["python-mode"] == [("C-c C-c", "send")]


def test_summarize_should_ignore_menu_and_mouse_bindings(tmp_path):
    make_stats_dir(tmp_path, bindings=[
        binding("<menu-bar> <file> <new-file>", "find-file"),
        binding("<tool-bar> <new-file>", "find-file"),
        binding("<mouse-1>", "mouse-set-point"),
        binding("<remap> <kill-line>", "my-kill-line"),
        binding("C-f", "forward-char"),
    ])
    report = summarize_dir(tmp_path)
    assert report.unused_bindings["global"] == [("C-f", "forward-char")]


def test_summarize_should_ignore_noise_commands_in_unused_bindings(tmp_path):
    make_stats_dir(tmp_path, bindings=[
        binding("C-u", "universal-argument"),
        binding("M-5", "digit-argument"),
        binding("a", "self-insert-command"),
    ])
    report = summarize_dir(tmp_path)
    assert report.unused_bindings["global"] == []


def test_summarize_should_count_mouse_events(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("mouse-set-point", "<down-mouse-1> <mouse-1>", count=1),
        event("forward-char", "C-f", count=3),
    ])
    report = summarize_dir(tmp_path)
    assert report.mouse_count == 1
    assert report.total == 4


def test_summarize_should_bucket_events_by_hour_in_local_time(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("a", "C-a", count=2, ts="2026-09-11T10:05:00+0900"),
        event("b", "C-b", count=1, ts="2026-09-11T23:30:00+0900"),
    ])
    report = summarize_dir(tmp_path)
    assert report.by_hour[10] == 2
    assert report.by_hour[23] == 1
    assert sum(report.by_hour) == 3


def test_summarize_should_bucket_events_by_weekday(tmp_path):
    # 2026-09-11 is a Friday.
    make_stats_dir(tmp_path, events=[event("a", "C-a", count=2)])
    report = summarize_dir(tmp_path)
    assert report.by_weekday[4] == 2


def test_summarize_should_rank_modes_by_usage(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("a", "C-a", count=1, mode="org-mode"),
        event("b", "C-b", count=5, mode="python-mode"),
    ])
    report = summarize_dir(tmp_path)
    assert [(m.mode, m.count) for m in report.by_mode] == [
        ("python-mode", 5), ("org-mode", 1)]


def test_summarize_should_handle_empty_input(tmp_path):
    report = summarize_dir(make_stats_dir(tmp_path))
    assert report.total == 0
    assert report.top_commands == []


# Rendering


def test_render_text_should_mention_top_command(tmp_path):
    make_stats_dir(tmp_path, events=[event("forward-char", "C-f", count=3)])
    text = keybind_stats.render_text(summarize_dir(tmp_path))
    assert "forward-char" in text
    assert "C-f" in text


def test_render_html_should_escape_keys(tmp_path):
    make_stats_dir(tmp_path, events=[event("forward-char", "<right>", count=3)])
    page = keybind_stats.render_html(summarize_dir(tmp_path))
    assert "&lt;right&gt;" in page
    assert "<right>" not in page


def test_render_html_should_list_forgotten_bindings(tmp_path):
    make_stats_dir(tmp_path, events=[
        event("goto-line", "M-x", count=4, mx=True, bound="M-g")])
    page = keybind_stats.render_html(summarize_dir(tmp_path))
    assert "goto-line" in page
    assert "M-g" in page


# Command line


def test_main_should_print_text_report(tmp_path, capsys):
    make_stats_dir(tmp_path, events=[event("forward-char", "C-f", count=3)])
    keybind_stats.main(["--dir", str(tmp_path)])
    assert "forward-char" in capsys.readouterr().out


def test_main_should_write_html_report(tmp_path):
    make_stats_dir(tmp_path, events=[event("forward-char", "C-f", count=3)])
    output = tmp_path / "report.html"
    keybind_stats.main(["--dir", str(tmp_path), "--html", str(output)])
    assert "forward-char" in output.read_text()


def test_main_should_limit_to_recent_days(tmp_path, capsys):
    make_stats_dir(tmp_path, events=[
        event("ancient", "C-a", ts="2000-01-01T10:00:00+0900"),
        event("recent", "C-b", ts=datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%S%z")),
    ])
    keybind_stats.main(["--dir", str(tmp_path), "--days", "7"])
    out = capsys.readouterr().out
    assert "recent" in out
    assert "ancient" not in out


if __name__ == "__main__":
    sys.exit(pytest.main([__file__]))
