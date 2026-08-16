#!/usr/bin/env python3
"""Report which file lines can carry an inline review comment on a pull request.

GitHub rejects a review comment whose anchor is not part of the pull request
diff, and it rejects the *whole* review rather than the offending comment, so a
single bad line number loses every finding. This script answers the question up
front: for each changed file, which new-side line numbers are anchorable.

Usage:
    list_commentable_lines.py                     # every file in the PR
    list_commentable_lines.py --path cmd/up.go    # one file
    list_commentable_lines.py --check findings.json

Example output:

    $ list_commentable_lines.py
    assets/logo.png: (no anchorable lines)
    cmd/up.go: 12-18, 40, 55-57
    docs/README.md: 1-5, 12

    $ list_commentable_lines.py --check findings.json
    ok      cmd/up.go:40
    INVALID cmd/up.go:41 - not in the diff; nearest anchorable line is 40
    INVALID cmd/old.go:7 - file is not in the pull request diff

    2 invalid of 3 anchors

--check exits 1 when any anchor is bad, so a caller can gate posting the
review on it.

Run from anywhere inside the repository checkout.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from typing import Any

from commands import run_gh_command

HUNK_PREFIX = "@@"


def parse_hunk_header(line: str) -> tuple[int, int] | None:
    """Return (new_start, new_count) from a "@@ -a,b +c,d @@" header.

    An omitted count means one line, so "@@ -30 +32 @@" yields (32, 1). Returns
    None when the line is not a hunk header.
    """
    if not line.startswith(HUNK_PREFIX):
        return None
    for field in line.split():
        if not field.startswith("+"):
            continue
        spec = field[1:]
        if "," in spec:
            start_text, count_text = spec.split(",", 1)
        else:
            start_text, count_text = spec, "1"
        try:
            return int(start_text), int(count_text)
        except ValueError:
            return None
    return None


def collect_commentable_lines(patch: str) -> set[int]:
    """Return the set of new-side line numbers present in a unified diff patch.

    Both added and context lines are anchorable; removed lines exist only on the
    old side and do not advance the new-side counter.
    """
    commentable: set[int] = set()
    new_line = 0
    # splitlines drops the trailing element that a final newline would add,
    # while keeping genuine blank context lines inside the patch.
    for line in patch.splitlines():
        header = parse_hunk_header(line)
        if header is not None:
            new_line = header[0]
            continue
        if new_line == 0 or line.startswith("\\"):
            continue
        if line.startswith("-"):
            continue
        # "+" is an added line; " " and "" are context.
        commentable.add(new_line)
        new_line += 1
    return commentable


def find_pull_request_number() -> int:
    """Return the pull request number for the current branch."""
    output = run_gh_command(["gh", "pr", "view", "--json", "number"])
    return json.loads(output)["number"]


def find_repository() -> str:
    """Return the current repository as "owner/name"."""
    output = run_gh_command(["gh", "repo", "view", "--json", "nameWithOwner"])
    return json.loads(output)["nameWithOwner"]


def fetch_pull_request_files(repository: str, pr_number: int) -> list[dict[str, Any]]:
    """Return the pull request's changed files as a list of API objects.

    Uses newline-delimited JSON so pagination works across gh versions.
    """
    output = run_gh_command([
        "gh", "api", "--paginate",
        f"repos/{repository}/pulls/{pr_number}/files",
        "--jq", ".[]",
    ])
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def build_commentable_index(files: Sequence[dict[str, Any]]) -> dict[str, set[int]]:
    """Return {path: set of anchorable new-side line numbers} for the PR."""
    index: dict[str, set[int]] = {}
    for changed_file in files:
        patch = changed_file.get("patch")
        if patch is None:
            # Binary files and very large diffs come back without a patch.
            index[changed_file["filename"]] = set()
            continue
        index[changed_file["filename"]] = collect_commentable_lines(patch)
    return index


def format_line_ranges(lines: set[int]) -> str:
    """Render a set of line numbers as "1-5, 12, 40-44"."""
    if not lines:
        return "(no anchorable lines)"
    ordered = sorted(lines)
    parts: list[str] = []
    start = previous = ordered[0]
    for line in ordered[1:]:
        if line == previous + 1:
            previous = line
            continue
        parts.append(str(start) if start == previous else f"{start}-{previous}")
        start = previous = line
    parts.append(str(start) if start == previous else f"{start}-{previous}")
    return ", ".join(parts)


def find_nearest_line(lines: set[int], target: int) -> int | None:
    """Return the anchorable line closest to target, or None if there is none."""
    if not lines:
        return None
    return min(lines, key=lambda line: (abs(line - target), line))


def check_findings(index: dict[str, set[int]], findings_path: str) -> int:
    """Print a verdict per finding anchor. Returns the number of bad anchors."""
    with open(findings_path, encoding="utf-8") as handle:
        findings = json.load(handle)
    bad_count = 0
    for comment in findings.get("comments", []):
        path = comment.get("path")
        line = comment.get("line")
        lines = index.get(path)
        if lines is None:
            print(f"INVALID {path}:{line} - file is not in the pull request diff")
            bad_count += 1
        elif line not in lines:
            nearest = find_nearest_line(lines, line)
            hint = f"nearest anchorable line is {nearest}" if nearest else "no anchorable lines"
            print(f"INVALID {path}:{line} - not in the diff; {hint}")
            bad_count += 1
        else:
            print(f"ok      {path}:{line}")
    print(f"\n{bad_count} invalid of {len(findings.get('comments', []))} anchors")
    return bad_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", type=int, help="pull request number (default: current branch)")
    parser.add_argument("--repo", help='repository as "owner/name" (default: current)')
    parser.add_argument("--path", action="append", help="restrict output to this file")
    parser.add_argument("--check", help="validate the anchors in a findings JSON file")
    args = parser.parse_args()

    try:
        repository = args.repo or find_repository()
        pr_number = args.pr or find_pull_request_number()
        files = fetch_pull_request_files(repository, pr_number)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    index = build_commentable_index(files)

    if args.check:
        return 1 if check_findings(index, args.check) else 0

    for path in sorted(index):
        if args.path and path not in args.path:
            continue
        print(f"{path}: {format_line_ranges(index[path])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
