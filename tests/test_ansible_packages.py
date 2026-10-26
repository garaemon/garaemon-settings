"""Tests for the package lists that the apt and homebrew roles install.

The apt role installs its packages in one transaction, so a single name that
the archive no longer ships fails the whole role.
"""

import re
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
ROLES_DIR = REPO_ROOT / "ansible" / "roles"
PACKAGE_TASK_FILES = [
    ROLES_DIR / "apt" / "tasks" / "main.yml",
    ROLES_DIR / "homebrew" / "tasks" / "main.yml",
]

# Matches bare scalar list items such as "      - zsh". Task entries such as
# "- name: ..." contain a colon and therefore never match.
PACKAGE_ITEM_PATTERN = re.compile(r"^\s*-\s+([A-Za-z0-9][\w.+-]*)\s*$")


def read_package_names(task_file):
    """Return every bare list item in task_file, which covers package names."""
    return {
        match.group(1)
        for line in task_file.read_text().splitlines()
        if (match := PACKAGE_ITEM_PATTERN.match(line))
    }


@pytest.mark.parametrize(
    "task_file", PACKAGE_TASK_FILES, ids=lambda path: path.parent.parent.name
)
def test_should_not_install_ccls(task_file):
    package_names = read_package_names(task_file)

    assert "ccls" not in package_names


def test_should_not_keep_ccls_role():
    ccls_role_dir = ROLES_DIR / "ccls"

    assert not ccls_role_dir.exists()
