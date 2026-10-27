"""Tests for the Ubuntu releases that the ghostty_install role supports.

The role downloads a release-specific deb from mkasberg/ghostty-ubuntu and
skips every release outside its supported list.
"""

import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
GHOSTTY_TASKS = (
    REPO_ROOT / "ansible" / "roles" / "ghostty_install" / "tasks" / "main.yml"
)
SUPPORTED_VERSIONS_PATTERN = re.compile(
    r"ghostty_install_supported_versions:\s*\[(?P<versions>[^\]]*)\]"
)
IS_SUPPORTED_VERSIONS_PATTERN = re.compile(
    r"distribution_version in \[(?P<versions>[^\]]*)\]"
)


def read_versions(pattern):
    """Return the quoted items of the first list that pattern matches."""
    match = pattern.search(GHOSTTY_TASKS.read_text())
    return re.findall(r"'([^']+)'", match.group("versions"))


def test_should_list_ubuntu_26_04_as_supported():
    supported_versions = read_versions(SUPPORTED_VERSIONS_PATTERN)

    assert "26.04" in supported_versions


def test_should_install_on_ubuntu_26_04():
    installable_versions = read_versions(IS_SUPPORTED_VERSIONS_PATTERN)

    assert "26.04" in installable_versions
