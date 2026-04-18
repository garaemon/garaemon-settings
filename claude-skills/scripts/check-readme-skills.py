#!/usr/bin/env python3
"""Verify that README.md links to every skill under .claude/skills/.

A skill is any directory under .claude/skills/ that contains a SKILL.md.
Each such skill must appear in README.md as a link whose target is the
relative path `.claude/skills/<name>/SKILL.md`.

Exit codes:
  0: all skills are linked (or no skills exist yet).
  1: at least one skill is missing from README.md, or README.md is absent.
"""

from __future__ import annotations

import sys
from pathlib import Path

README_PATH = Path("README.md")
SKILLS_ROOT = Path(".claude/skills")


def find_unlinked_skills(readme_text: str) -> list[str]:
    """Return the names of skills not referenced by their SKILL.md path."""
    unlinked: list[str] = []
    for skill_dir in sorted(p for p in SKILLS_ROOT.iterdir() if p.is_dir()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue
        expected_link = str(skill_md)
        if expected_link not in readme_text:
            unlinked.append(skill_dir.name)
    return unlinked


def count_skills() -> int:
    return sum(
        1
        for skill_dir in SKILLS_ROOT.iterdir()
        if skill_dir.is_dir() and (skill_dir / "SKILL.md").is_file()
    )


def main() -> int:
    if not README_PATH.is_file():
        print(f"error: {README_PATH} not found", file=sys.stderr)
        return 1

    if not SKILLS_ROOT.is_dir():
        print("No skills directory found; nothing to check.")
        return 0

    if count_skills() == 0:
        print("No skills with SKILL.md found; nothing to check.")
        return 0

    unlinked = find_unlinked_skills(README_PATH.read_text(encoding="utf-8"))

    if unlinked:
        print(
            f"{README_PATH} is missing links for the following skills:",
            file=sys.stderr,
        )
        for name in unlinked:
            print(f"  - {name}", file=sys.stderr)
        print(
            f"\nEach skill under {SKILLS_ROOT}/<name>/SKILL.md must be linked from "
            f"{README_PATH} using its path, e.g. "
            f"[<name>]({SKILLS_ROOT}/<name>/SKILL.md).",
            file=sys.stderr,
        )
        return 1

    print(f"All skills are linked in {README_PATH}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
