#!/usr/bin/env python3
"""Verify that README.md links to every skill under skills/.

A skill is any directory under skills/ that contains a SKILL.md.
Each such skill must appear in README.md as a link whose target is exactly
the relative path `skills/<name>/SKILL.md`.

Exit codes:
  0: all skills are linked (or no skills exist yet).
  1: at least one skill is missing from README.md, or README.md or the skills
     directory is absent.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

README_PATH = Path("README.md")
SKILLS_ROOT = Path("skills")
COMPONENT_ROOT = Path(__file__).resolve().parent.parent


def find_unlinked_skills(readme_text: str) -> list[str]:
    """Return the names of skills not referenced by their SKILL.md path."""
    unlinked: list[str] = []
    for skill_dir in sorted(p for p in SKILLS_ROOT.iterdir() if p.is_dir()):
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue
        # Match the link target, not a bare path: "skills/x/SKILL.md" is a
        # substring of the ".claude/skills/x/SKILL.md" this tree used to use,
        # so a link left behind at the old path would still count as present.
        expected_link = f"]({skill_md})"
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
    # README_PATH and SKILLS_ROOT stay relative because the link text checked
    # below is relative. Move to the component so they resolve wherever the
    # caller happens to stand.
    os.chdir(COMPONENT_ROOT)

    if not README_PATH.is_file():
        print(f"error: {README_PATH} not found", file=sys.stderr)
        return 1

    if not SKILLS_ROOT.is_dir():
        print(f"error: {SKILLS_ROOT} not found under {COMPONENT_ROOT}", file=sys.stderr)
        return 1

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
