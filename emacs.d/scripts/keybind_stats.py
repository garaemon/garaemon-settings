#!/usr/bin/env python3
"""Report which Emacs key bindings are used, forgotten, or missing.

Reads the JSON lines that lisp/my-keybind-stats.el writes under
~/.emacs.d/keybind-stats/ and prints a text report. With --html the same
report is written as a self-contained page.

Usage:
    python scripts/keybind_stats.py [--dir DIR] [--days N] [--top N]
                                    [--html report.html]
"""

import argparse
import html
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json

DEFAULT_DIRECTORY = Path.home() / ".emacs.d" / "keybind-stats"

# Bindings that say nothing about typing habits: menu and tool bars, mouse
# buttons, and remaps, which key-description renders as <remap> <command>.
IGNORED_KEY_PREFIXES = (
    "<menu-bar>", "<tool-bar>", "<tab-bar>", "<remap>", "<mouse", "<down-mouse",
    "<drag-mouse", "<double-mouse", "<triple-mouse", "<wheel", "<touch",
    "<mode-line>", "<header-line>", "<vertical-line>", "<left-fringe>",
    "<right-fringe>", "<left-margin>", "<right-margin>",
)

# Commands that every key sequence passes through or that carry no intent.
NOISE_COMMANDS = frozenset({
    "self-insert-command", "digit-argument", "negative-argument",
    "universal-argument", "universal-argument-more", "undefined", "ignore",
})

MOUSE_KEY_PREFIXES = ("<mouse", "<down-mouse", "<drag-mouse", "<double-mouse",
                      "<triple-mouse", "<wheel")

WEEKDAY_NAMES = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

LONG_SEQUENCE_CHORDS = 3
UNBOUND_FAVORITE_MIN_COUNT = 2


@dataclass(frozen=True)
class Event:
    """One aggregated row of the event log."""

    ts: datetime
    command: str
    keys: str
    mode: str
    mx: bool
    bound: str | None
    count: int


@dataclass
class CommandUsage:
    command: str
    count: int
    keys: list[tuple[str, int]] = field(default_factory=list)


@dataclass
class ModeUsage:
    mode: str
    count: int
    top_commands: list[CommandUsage] = field(default_factory=list)


@dataclass
class Report:
    total: int = 0
    mouse_count: int = 0
    first_ts: datetime | None = None
    last_ts: datetime | None = None
    top_commands: list[CommandUsage] = field(default_factory=list)
    forgotten_bindings: list[tuple[str, str, int]] = field(default_factory=list)
    unbound_favorites: list[tuple[str, int]] = field(default_factory=list)
    long_sequences: list[tuple[str, str, int]] = field(default_factory=list)
    unused_bindings: dict[str, list[tuple[str, str]]] = field(default_factory=dict)
    by_mode: list[ModeUsage] = field(default_factory=list)
    by_hour: list[int] = field(default_factory=lambda: [0] * 24)
    by_weekday: list[int] = field(default_factory=lambda: [0] * 7)


# Loading


def parse_timestamp(text):
    """Parse the %Y-%m-%dT%H:%M:%S%z stamp that Emacs writes."""
    return datetime.strptime(text, "%Y-%m-%dT%H:%M:%S%z")


def parse_event(line):
    row = json.loads(line)
    return Event(
        ts=parse_timestamp(row["ts"]),
        command=row["command"],
        keys=row["keys"],
        mode=row["mode"],
        mx=bool(row.get("mx")),
        bound=row.get("bound"),
        count=int(row.get("count", 1)),
    )


def read_json_lines(path):
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                yield line


def load_events(directory, since):
    """Return every event at or after SINCE, across all monthly files."""
    directory = Path(directory)
    if not directory.is_dir():
        return []
    events = []
    for path in sorted(directory.glob("events-*.jsonl")):
        for line in read_json_lines(path):
            event = parse_event(line)
            if since is None or event.ts >= since:
                events.append(event)
    return events


def load_bindings(directory):
    """Return {scope: [(keys, command), ...]} from the binding snapshots."""
    bindings = {}
    bindings_dir = Path(directory) / "bindings"
    if not bindings_dir.is_dir():
        return bindings
    for path in sorted(bindings_dir.glob("*.jsonl")):
        rows = [json.loads(line) for line in read_json_lines(path)]
        if rows:
            scope = rows[0]["scope"]
            bindings[scope] = [(row["keys"], row["command"]) for row in rows]
    return bindings


# Summary


def count_chords(keys):
    return len(keys.split())


def is_mouse_keys(keys):
    return keys.startswith(MOUSE_KEY_PREFIXES)


def is_ignored_binding(keys, command):
    return keys.startswith(IGNORED_KEY_PREFIXES) or command in NOISE_COMMANDS


def rank_commands(events, top):
    """Return the TOP most used commands with their key breakdown."""
    totals = Counter()
    keys_per_command = defaultdict(Counter)
    for event in events:
        totals[event.command] += event.count
        keys_per_command[event.command][event.keys] += event.count
    return [
        CommandUsage(command, count, keys_per_command[command].most_common())
        for command, count in totals.most_common(top)
    ]


def find_forgotten_bindings(events):
    """Return (command, bound key, count) for M-x calls that had a key."""
    totals = Counter()
    bound_keys = {}
    for event in events:
        if event.mx and event.bound:
            totals[event.command] += event.count
            bound_keys[event.command] = event.bound
    return [(command, bound_keys[command], count)
            for command, count in totals.most_common()]


def find_unbound_favorites(events):
    """Return (command, count) for commands run via M-x that have no key."""
    totals = Counter()
    for event in events:
        if event.mx and not event.bound:
            totals[event.command] += event.count
    return [(command, count) for command, count in totals.most_common()
            if count >= UNBOUND_FAVORITE_MIN_COUNT]


def find_long_sequences(events):
    """Return (keys, command, count) for sequences of three chords or more."""
    totals = Counter()
    for event in events:
        if not event.mx and count_chords(event.keys) >= LONG_SEQUENCE_CHORDS:
            totals[(event.keys, event.command)] += event.count
    return [(keys, command, count)
            for (keys, command), count in totals.most_common()]


def find_unused_bindings(events, bindings):
    """Return {scope: [(keys, command), ...]} for bindings never pressed.

    A global binding counts as used when its key appears in any mode. A
    mode binding counts as used only when its key appears in that mode.
    """
    used_anywhere = {event.keys for event in events if not event.mx}
    used_per_mode = defaultdict(set)
    for event in events:
        if not event.mx:
            used_per_mode[event.mode].add(event.keys)
    unused = {}
    for scope, scope_bindings in bindings.items():
        used = used_anywhere if scope == "global" else used_per_mode[scope]
        unused[scope] = sorted(
            (keys, command) for keys, command in scope_bindings
            if keys not in used and not is_ignored_binding(keys, command))
    return unused


def rank_modes(events, top):
    per_mode = defaultdict(list)
    for event in events:
        per_mode[event.mode].append(event)
    modes = [
        ModeUsage(mode, sum(e.count for e in mode_events),
                  rank_commands(mode_events, top))
        for mode, mode_events in per_mode.items()
    ]
    return sorted(modes, key=lambda usage: usage.count, reverse=True)


def bucket_by_time(events):
    """Return (per hour, per weekday) counts in the log's own time zone."""
    by_hour = [0] * 24
    by_weekday = [0] * 7
    for event in events:
        by_hour[event.ts.hour] += event.count
        by_weekday[event.ts.weekday()] += event.count
    return by_hour, by_weekday


def summarize(events, bindings, top=30):
    report = Report()
    report.total = sum(event.count for event in events)
    report.mouse_count = sum(event.count for event in events
                             if is_mouse_keys(event.keys))
    if events:
        report.first_ts = min(event.ts for event in events)
        report.last_ts = max(event.ts for event in events)
    report.top_commands = rank_commands(events, top)
    report.forgotten_bindings = find_forgotten_bindings(events)
    report.unbound_favorites = find_unbound_favorites(events)
    report.long_sequences = find_long_sequences(events)
    report.unused_bindings = find_unused_bindings(events, bindings)
    report.by_mode = rank_modes(events, top=5)
    report.by_hour, report.by_weekday = bucket_by_time(events)
    return report


# Text rendering


def format_period(report):
    if report.first_ts is None:
        return "no events"
    return "%s to %s" % (report.first_ts.strftime("%Y-%m-%d"),
                         report.last_ts.strftime("%Y-%m-%d"))


def format_keys_breakdown(keys):
    return ", ".join("%s (%d)" % (key, count) for key, count in keys)


def render_text_section(title, lines):
    if not lines:
        lines = ["(nothing)"]
    return ["", "## " + title, ""] + lines


def render_text_unused(report, limit):
    lines = []
    for scope, unused in report.unused_bindings.items():
        lines.append("%s: %d unused" % (scope, len(unused)))
        for keys, command in unused[:limit]:
            lines.append("  %-20s %s" % (keys, command))
        if len(unused) > limit:
            lines.append("  ... and %d more" % (len(unused) - limit))
    return lines


def render_text_histogram(labels, values):
    peak = max(values) if values and max(values) > 0 else 1
    return ["%-4s %6d %s" % (label, value, "#" * int(40 * value / peak))
            for label, value in zip(labels, values)]


def render_text(report, unused_limit=40):
    """Return the report as plain text for the terminal."""
    lines = ["# Emacs keybinding stats", "",
             "Period: %s" % format_period(report),
             "Commands: %d (mouse: %d)" % (report.total, report.mouse_count)]
    lines += render_text_section("Top commands", [
        "%6d  %-40s %s" % (usage.count, usage.command,
                           format_keys_breakdown(usage.keys))
        for usage in report.top_commands])
    lines += render_text_section("Forgotten bindings (run via M-x but bound)", [
        "%6d  %-40s %s" % (count, command, bound)
        for command, bound, count in report.forgotten_bindings])
    lines += render_text_section("Unbound favorites (run via M-x, no key)", [
        "%6d  %s" % (count, command)
        for command, count in report.unbound_favorites])
    lines += render_text_section("Long key sequences", [
        "%6d  %-20s %s" % (count, keys, command)
        for keys, command, count in report.long_sequences])
    lines += render_text_section("Unused bindings",
                                 render_text_unused(report, unused_limit))
    lines += render_text_section("By major mode", [
        "%6d  %-30s %s" % (usage.count, usage.mode,
                           ", ".join(c.command for c in usage.top_commands))
        for usage in report.by_mode])
    lines += render_text_section("By hour", render_text_histogram(
        ["%02d" % hour for hour in range(24)], report.by_hour))
    lines += render_text_section("By weekday", render_text_histogram(
        WEEKDAY_NAMES, report.by_weekday))
    return "\n".join(lines) + "\n"


# HTML rendering


HTML_STYLE = """
:root {
  color-scheme: light dark;
  --surface: #fcfcfb;
  --surface-2: #f1f0ec;
  --text: #0b0b0b;
  --text-2: #52514e;
  --line: #d9d8d3;
  --bar: #2a78d6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --surface: #1a1a19;
    --surface-2: #262625;
    --text: #ffffff;
    --text-2: #c3c2b7;
    --line: #3d3d3a;
    --bar: #3987e5;
  }
}
body { margin: 0; padding: 24px 16px; background: var(--surface);
  color: var(--text); font: 14px/1.5 system-ui, sans-serif; }
main { max-width: 960px; margin: 0 auto; }
h1 { font-size: 22px; margin: 0 0 4px; }
h2 { font-size: 16px; margin: 32px 0 8px; }
p.meta { color: var(--text-2); margin: 0 0 8px; }
p.hint { color: var(--text-2); margin: 0 0 12px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: 4px 8px; border-bottom: 1px solid var(--line);
  vertical-align: top; }
th { color: var(--text-2); font-weight: 600; }
td.num { text-align: right; font-variant-numeric: tabular-nums; width: 5em; }
td.bar { width: 40%; }
.track { height: 10px; background: var(--surface-2); border-radius: 4px; }
.fill { height: 10px; background: var(--bar); border-radius: 0 4px 4px 0; }
.fill:hover { filter: brightness(1.15); }
kbd { font-family: ui-monospace, monospace; background: var(--surface-2);
  padding: 0 4px; border-radius: 3px; }
code { font-family: ui-monospace, monospace; }
th, td.num { white-space: nowrap; }
svg.hist { width: 100%; height: auto; max-height: 160px; display: block; }
svg.hist rect { fill: var(--bar); }
svg.hist rect:hover { filter: brightness(1.15); }
svg.hist text { fill: var(--text-2); font-size: 9px; text-anchor: middle; }
details summary { cursor: pointer; margin: 8px 0; }
"""


def escape(text):
    return html.escape(str(text), quote=True)


def render_html_bar(count, peak):
    width = 100.0 * count / peak if peak else 0
    return ('<td class="bar"><div class="track"><div class="fill" '
            'style="width:%.1f%%" title="%d"></div></div></td>'
            % (width, count))


def render_html_table(headers, rows, bar_column=None):
    """Return a table; BAR_COLUMN names the numeric column to draw as a bar."""
    if not rows:
        return "<p class=\"meta\">Nothing to show.</p>"
    peak = max(row[bar_column] for row in rows) if bar_column is not None else 0
    parts = ["<table><thead><tr>"]
    parts += ["<th>%s</th>" % escape(header) for header in headers]
    if bar_column is not None:
        parts.append("<th></th>")
    parts.append("</tr></thead><tbody>")
    for row in rows:
        parts.append("<tr>")
        for index, cell in enumerate(row):
            css = ' class="num"' if isinstance(cell, int) else ""
            parts.append("<td%s>%s</td>" % (css, cell if isinstance(cell, int)
                                             else escape(cell)))
        if bar_column is not None:
            parts.append(render_html_bar(row[bar_column], peak))
        parts.append("</tr>")
    parts.append("</tbody></table>")
    return "".join(parts)


def render_html_histogram(labels, values):
    """Return an inline SVG column chart with one column per label."""
    peak = max(values) if values and max(values) > 0 else 1
    slot, plot_height, label_height = 24, 120, 16
    parts = ['<svg class="hist" viewBox="0 0 %d %d" role="img">'
             % (slot * len(labels), plot_height + label_height)]
    for index, (label, value) in enumerate(zip(labels, values)):
        height = plot_height * value / peak
        parts.append('<rect x="%d" y="%.1f" width="%d" height="%.1f" rx="4">'
                     '<title>%s: %d</title></rect>'
                     % (slot * index + 2, plot_height - height, slot - 4,
                        height, escape(label), value))
        parts.append('<text x="%d" y="%d">%s</text>'
                     % (slot * index + slot // 2, plot_height + 12,
                        escape(label)))
    parts.append("</svg>")
    return "".join(parts)


def render_html_unused(report):
    parts = []
    for scope, unused in report.unused_bindings.items():
        parts.append("<details><summary>%s: %d unused</summary>" % (
            escape(scope), len(unused)))
        parts.append(render_html_table(["Keys", "Command"], unused))
        parts.append("</details>")
    return "".join(parts) or "<p class=\"meta\">No binding snapshot yet.</p>"


def render_html_modes(report):
    rows = [(usage.mode, usage.count,
             ", ".join(c.command for c in usage.top_commands))
            for usage in report.by_mode]
    return render_html_table(["Mode", "Commands", "Most used"], rows,
                             bar_column=1)


def render_html_sections(report):
    """Return the section list as (title, hint, body html)."""
    top_rows = [(usage.command, usage.count, format_keys_breakdown(usage.keys))
                for usage in report.top_commands]
    return [
        ("Top commands", "Which commands carry the day.",
         render_html_table(["Command", "Count", "Keys"], top_rows, bar_column=1)),
        ("Forgotten bindings",
         "Run through M-x although a key exists. Relearn the key.",
         render_html_table(["Command", "Bound key", "M-x count"],
                           report.forgotten_bindings, bar_column=2)),
        ("Unbound favorites",
         "Run through M-x at least twice and bound to no key. Bind them.",
         render_html_table(["Command", "M-x count"], report.unbound_favorites,
                           bar_column=1)),
        ("Long key sequences",
         "Three chords or more. Frequent ones deserve a shorter key.",
         render_html_table(["Keys", "Command", "Count"], report.long_sequences,
                           bar_column=2)),
        ("Unused bindings",
         "Bound keys that never appear in the log. Candidates to relearn or reuse.",
         render_html_unused(report)),
        ("By major mode", "", render_html_modes(report)),
        ("By hour", "", render_html_histogram(
            ["%02d" % hour for hour in range(24)], report.by_hour)),
        ("By weekday", "", render_html_histogram(WEEKDAY_NAMES,
                                                 report.by_weekday)),
    ]


def render_html(report):
    """Return the report as a self-contained HTML page."""
    parts = ["<!doctype html><html><head><meta charset=\"utf-8\">",
             "<meta name=\"viewport\" content=\"width=device-width\">",
             "<title>Emacs keybinding stats</title>",
             "<style>%s</style></head><body><main>" % HTML_STYLE,
             "<h1>Emacs keybinding stats</h1>",
             "<p class=\"meta\">Period: %s. Commands: %d, of which mouse: %d.</p>"
             % (escape(format_period(report)), report.total, report.mouse_count)]
    for title, hint, body in render_html_sections(report):
        parts.append("<h2>%s</h2>" % escape(title))
        if hint:
            parts.append("<p class=\"hint\">%s</p>" % escape(hint))
        parts.append(body)
    parts.append("</main></body></html>")
    return "\n".join(parts)


# Command line


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", default=str(DEFAULT_DIRECTORY),
                        help="stats directory (default: %(default)s)")
    parser.add_argument("--days", type=int, default=None,
                        help="only count the last N days")
    parser.add_argument("--top", type=int, default=30,
                        help="rows per ranking (default: %(default)s)")
    parser.add_argument("--html", default=None, metavar="FILE",
                        help="write an HTML report to FILE instead of text")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    since = None
    if args.days is not None:
        since = datetime.now(timezone.utc) - timedelta(days=args.days)
    events = load_events(args.dir, since)
    bindings = load_bindings(args.dir)
    report = summarize(events, bindings, top=args.top)
    if args.html:
        Path(args.html).write_text(render_html(report), encoding="utf-8")
        print("wrote %s" % args.html)
    else:
        sys.stdout.write(render_text(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
