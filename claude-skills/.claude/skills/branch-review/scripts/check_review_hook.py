#!/usr/bin/env python3
"""PostToolUse hook that checks a review.json file the moment it is written.

Claude Code runs this after every Write or Edit while the branch-review skill
is active, with the tool call as JSON on stdin. Writes to any file other than
a review.json are ignored, and so is a review.json that does not carry a
"categories" key, since a project under review may keep a file of that name
for its own purposes. For a review the hook runs the same checks as
render_review.py and, when any fail, exits with status 2 and the problems on
stderr, which Claude Code feeds back to the model so the file gets fixed
before the reports are rendered.

Usage (from a SKILL.md hooks entry, which cannot use ${CLAUDE_SKILL_DIR}):
    uv run --project $HOME/.claude/skills/branch-review $HOME/.claude/skills/branch-review/scripts/check_review_hook.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from commands import run_command
from render_review import check_review, report_problems, validate_review

REVIEW_FILE_NAME = "review.json"


def select_review_path(payload: dict[str, Any]) -> Path | None:
    """Return the written file when it is a review.json, else None."""
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    file_path = tool_input.get("file_path")
    if not isinstance(file_path, str) or Path(file_path).name != REVIEW_FILE_NAME:
        return None
    return Path(file_path)


def is_review_shaped(document: Any) -> bool:
    """Return whether the JSON is this skill's review rather than an unrelated file."""
    return isinstance(document, dict) and "categories" in document


def find_checkout_root(fallback: Path) -> Path:
    """Return the git checkout root, or fallback when the cwd is not in one."""
    output = run_command(["git", "rev-parse", "--show-toplevel"], check=False).strip()
    return Path(output) if output else fallback


def check_written_review(payload_text: str, root: Path) -> int:
    """Check the review named in the hook payload and return the exit status."""
    try:
        payload = json.loads(payload_text)
    except json.JSONDecodeError:
        # Hook input this script cannot read is not the model's mistake, and
        # failing here would turn every write into an error.
        return 0
    if not isinstance(payload, dict):
        return 0
    review_path = select_review_path(payload)
    if review_path is None:
        return 0
    try:
        document = json.loads(review_path.read_text(encoding="utf-8"))
    except (ValueError, OSError) as error:
        print(f"error: {review_path}: {error}", file=sys.stderr)
        return 2
    if not is_review_shaped(document):
        return 0
    try:
        validate_review(document)
        problems = check_review(document, root)
    except ValueError as error:
        print(f"error: {review_path}: {error}", file=sys.stderr)
        return 2
    if problems:
        report_problems(review_path, problems)
        return 2
    return 0


def main() -> int:
    return check_written_review(sys.stdin.read(), find_checkout_root(Path.cwd()))


if __name__ == "__main__":
    sys.exit(main())
