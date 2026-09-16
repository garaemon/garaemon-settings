"""Tests for the README skills-link check.

Run with: python3 -m unittest discover -s scripts/tests -t scripts/tests
"""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "check-readme-skills.py"


def load_checker():
    """Import the checker, whose filename is not a Python identifier."""
    spec = importlib.util.spec_from_file_location("check_readme_skills", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FindUnlinkedSkillsTest(unittest.TestCase):
    """find_unlinked_skills names the skills README.md does not link."""

    def setUp(self) -> None:
        self.checker = load_checker()
        self.skills_root = tempfile.TemporaryDirectory()
        self.addCleanup(self.skills_root.cleanup)
        self.checker.SKILLS_ROOT = Path(self.skills_root.name)

    def add_skill(self, name: str, with_skill_md: bool = True) -> None:
        """Create a skill directory, optionally without its SKILL.md."""
        skill_dir = self.checker.SKILLS_ROOT / name
        skill_dir.mkdir()
        if with_skill_md:
            (skill_dir / "SKILL.md").write_text("# skill\n", encoding="utf-8")

    def find_unlinked(self, readme_text: str) -> list[str]:
        return self.checker.find_unlinked_skills(readme_text)

    def test_accepts_a_link_to_the_skill(self) -> None:
        self.add_skill("branch-review")
        readme = f"- [branch-review]({self.checker.SKILLS_ROOT}/branch-review/SKILL.md)"
        self.assertEqual(self.find_unlinked(readme), [])

    def test_reports_a_skill_with_no_link(self) -> None:
        self.add_skill("branch-review")
        self.assertEqual(self.find_unlinked("nothing here"), ["branch-review"])

    def test_rejects_a_link_left_at_the_old_path(self) -> None:
        # The tree moved out of .claude/, and the old path ends with the new
        # one, so a substring match would call this link good.
        self.add_skill("branch-review")
        readme = (
            f"- [branch-review](.claude/{self.checker.SKILLS_ROOT}"
            "/branch-review/SKILL.md)"
        )
        self.assertEqual(self.find_unlinked(readme), ["branch-review"])

    def test_rejects_a_bare_path_that_is_not_a_link(self) -> None:
        self.add_skill("branch-review")
        readme = f"see {self.checker.SKILLS_ROOT}/branch-review/SKILL.md"
        self.assertEqual(self.find_unlinked(readme), ["branch-review"])

    def test_ignores_a_directory_without_a_skill_file(self) -> None:
        self.add_skill("scratch", with_skill_md=False)
        self.assertEqual(self.find_unlinked(""), [])

    def test_reports_every_unlinked_skill_in_order(self) -> None:
        self.add_skill("alpha")
        self.add_skill("beta")
        self.assertEqual(self.find_unlinked(""), ["alpha", "beta"])


class CountSkillsTest(unittest.TestCase):
    """count_skills counts the directories that carry a SKILL.md."""

    def setUp(self) -> None:
        self.checker = load_checker()
        self.skills_root = tempfile.TemporaryDirectory()
        self.addCleanup(self.skills_root.cleanup)
        self.checker.SKILLS_ROOT = Path(self.skills_root.name)

    def test_counts_only_directories_holding_a_skill_file(self) -> None:
        (self.checker.SKILLS_ROOT / "alpha").mkdir()
        (self.checker.SKILLS_ROOT / "alpha" / "SKILL.md").write_text("x")
        (self.checker.SKILLS_ROOT / "scratch").mkdir()
        self.assertEqual(self.checker.count_skills(), 1)

    def test_counts_nothing_in_an_empty_tree(self) -> None:
        self.assertEqual(self.checker.count_skills(), 0)


if __name__ == "__main__":
    unittest.main()
