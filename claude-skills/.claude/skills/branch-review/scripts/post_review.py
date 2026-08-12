#!/usr/bin/env python3
"""Validate a findings file and post it as inline pull request review comments.

GitHub rejects an entire review when any one comment anchors to a line outside
the diff, so this script checks every anchor first and refuses to post if any is
bad -- naming the offending line and the nearest usable one. That turns a
lost review into a fixable error message.

The findings file is the GitHub review payload with the boilerplate left out:

    {
      "body": "Overall comments, PR size notes, cross-cutting concerns.",
      "event": "COMMENT",
      "comments": [
        {"path": "cmd/up.go", "line": 36, "body": "### 1-1. ..."}
      ]
    }

"side": "RIGHT" is filled in for every comment, and "event" defaults to COMMENT.
Findings that cannot be anchored to a diff line belong in "body".

Usage:
    post_review.py findings.json --dry-run   # validate and show what would post
    post_review.py findings.json             # validate and post

Run from anywhere inside the repository checkout.
"""

import argparse
import json
import sys

from commands import run_gh_command
from list_commentable_lines import (
    build_commentable_index,
    fetch_pull_request_files,
    find_nearest_line,
    find_pull_request_number,
    find_repository,
)

VALID_EVENTS = ("COMMENT", "APPROVE", "REQUEST_CHANGES")


def load_findings(findings_path):
    """Read the findings file and return it as a review payload."""
    with open(findings_path, encoding="utf-8") as handle:
        findings = json.load(handle)
    if "comments" not in findings:
        findings["comments"] = []
    findings.setdefault("event", "COMMENT")
    if findings["event"] not in VALID_EVENTS:
        raise ValueError(
            f"event must be one of {', '.join(VALID_EVENTS)}, got {findings['event']!r}"
        )
    for comment in findings["comments"]:
        for field in ("path", "line", "body"):
            if field not in comment:
                raise ValueError(f"comment is missing {field!r}: {comment}")
        comment["side"] = "RIGHT"
    return findings


def validate_anchors(findings, index):
    """Return a list of human-readable problems with the comment anchors."""
    problems = []
    for comment in findings["comments"]:
        path, line = comment["path"], comment["line"]
        lines = index.get(path)
        if lines is None:
            problems.append(f"{path}:{line} - file is not in the pull request diff")
            continue
        if line not in lines:
            nearest = find_nearest_line(lines, line)
            hint = (
                f"nearest anchorable line is {nearest}"
                if nearest
                else "this file has no anchorable lines"
            )
            problems.append(f"{path}:{line} - not in the diff; {hint}")
    return problems


def submit_review(repository, pr_number, findings):
    """POST the review and return the created review object."""
    output = run_gh_command(
        [
            "gh", "api", "-X", "POST",
            f"repos/{repository}/pulls/{pr_number}/reviews",
            "--input", "-",
        ],
        input_text=json.dumps(findings),
    )
    return json.loads(output)


def count_posted_comments(repository, pr_number):
    """Return how many inline comments the pull request now carries."""
    output = run_gh_command([
        "gh", "api", "--paginate",
        f"repos/{repository}/pulls/{pr_number}/comments",
        "--jq", ".[].path",
    ])
    return len([line for line in output.splitlines() if line.strip()])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("findings", help="path to the findings JSON file")
    parser.add_argument("--pr", type=int, help="pull request number (default: current branch)")
    parser.add_argument("--repo", help='repository as "owner/name" (default: current)')
    parser.add_argument(
        "--dry-run", action="store_true",
        help="validate and print the anchors without posting",
    )
    args = parser.parse_args()

    try:
        findings = load_findings(args.findings)
        repository = args.repo or find_repository()
        pr_number = args.pr or find_pull_request_number()
        index = build_commentable_index(fetch_pull_request_files(repository, pr_number))
    except (RuntimeError, ValueError, json.JSONDecodeError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    problems = validate_anchors(findings, index)
    if problems:
        print("error: refusing to post; GitHub rejects the whole review on a bad anchor",
              file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1

    comment_count = len(findings["comments"])
    print(f"{comment_count} inline comments, all anchored to lines in the diff:")
    for comment in findings["comments"]:
        heading = comment["body"].splitlines()[0] if comment["body"] else ""
        print(f"  {comment['path']}:{comment['line']}  {heading}")

    if args.dry_run:
        print(f"\ndry run: nothing posted to #{pr_number}")
        return 0

    try:
        review = submit_review(repository, pr_number, findings)
        posted = count_posted_comments(repository, pr_number)
    except (RuntimeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"\nposted {review['state']} review: {review['html_url']}")
    print(f"inline comments now on #{pr_number}: {posted}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
