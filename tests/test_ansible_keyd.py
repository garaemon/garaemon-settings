"""Tests for the keyd role's handling of the keyd-team PPA.

The PPA publishes no suite for Ubuntu 26.04, and an apt source that points at
a missing suite makes `apt-get update` fail, so the role must register the
PPA only where it exists.
"""

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
KEYD_TASKS = REPO_ROOT / "ansible" / "roles" / "keyd" / "tasks" / "main.yml"
PPA_AVAILABLE_GUARD = re.compile(r"^\s*when:.*\bkeyd_ppa_available\b")


def find_task_line(lines, task_name):
    """Return the index of the line that starts the task named task_name."""
    return next(
        index
        for index, line in enumerate(lines)
        if line.strip() == f"- name: {task_name}"
    )


def read_indent(line):
    return len(line) - len(line.lstrip())


def read_enclosing_task_headers(lines, task_index):
    """Return the indices of the task and of every block that encloses it."""
    header_indices = [task_index]
    current_indent = read_indent(lines[task_index])
    for index in range(task_index - 1, -1, -1):
        line = lines[index]
        if line.lstrip().startswith("- ") and read_indent(line) < current_indent:
            header_indices.append(index)
            current_indent = read_indent(line)
    return header_indices


def read_task_keys(lines, header_index):
    """Return the lines of the task's own keys, excluding nested tasks."""
    key_indent = read_indent(lines[header_index]) + 2
    task_keys = [lines[header_index]]
    for line in lines[header_index + 1:]:
        if line.strip() and read_indent(line) < key_indent:
            break
        if read_indent(line) == key_indent:
            task_keys.append(line)
    return task_keys


def is_guarded_by_ppa_availability(task_name):
    lines = KEYD_TASKS.read_text().splitlines()
    task_index = find_task_line(lines, task_name)
    return any(
        PPA_AVAILABLE_GUARD.match(key_line)
        for header_index in read_enclosing_task_headers(lines, task_index)
        for key_line in read_task_keys(lines, header_index)
    )


def test_should_write_ppa_source_only_when_ppa_publishes_release():
    assert is_guarded_by_ppa_availability(
        "Write keyd PPA repository file with signed-by"
    )


def test_should_install_ppa_signing_key_only_when_ppa_publishes_release():
    assert is_guarded_by_ppa_availability(
        "Convert and install keyd PPA signing key to keyrings"
    )
