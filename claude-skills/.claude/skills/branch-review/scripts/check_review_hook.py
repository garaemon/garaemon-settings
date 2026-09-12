#!/usr/bin/env python3
"""PostToolUse hook that checks a review.json file the moment it is written.

Claude Code runs this after every Write or Edit while the branch-review skill
is active, with the tool call as JSON on stdin. Writes to any file other than
a review.json are ignored. For a review.json the hook runs the same checks as
render_review.py and, when any fail, exits with status 2 and the problems on
stderr, which Claude Code feeds back to the model so the file gets fixed
before the reports are rendered.

Usage (from a SKILL.md hooks entry):
    uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/check_review_hook.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from commands import run_command
from render_review import check_review, load_review, report_problems

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


def find_checkout_root(fallback: Path) -> Path:
    """Return the git checkout root, or fallback when the cwd is not in one."""
    output = run_command(["git", "rev-parse", "--show-toplevel"], check=False).strip()
    return Path(output) if output else fallback


def run(payload_text: str, root: Path) -> int:
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
        problems = check_review(load_review(review_path), root)
    except (ValueError, OSError) as error:
        print(f"error: {review_path}: {error}", file=sys.stderr)
        return 2
    if problems:
        report_problems(review_path, problems)
        return 2
    return 0


def main() -> int:
    return run(sys.stdin.read(), find_checkout_root(Path.cwd()))


if __name__ == "__main__":
    sys.exit(main())
