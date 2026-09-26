"""Keep repository-only files at the top of the chezmoi source directory out
of the home directory.

chezmoi installs every top-level entry that .chezmoiignore does not list, so
a plain name such as LICENSE lands in ~ unless it is ignored explicitly.
"""

from pathlib import Path

import pytest


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
CHEZMOIIGNORE = DOTFILES_ROOT / ".chezmoiignore.tmpl"
# Source attributes from https://www.chezmoi.io/reference/source-state-attributes/
CHEZMOI_SOURCE_PREFIXES = (
    "create_",
    "dot_",
    "empty_",
    "encrypted_",
    "exact_",
    "executable_",
    "external_",
    "literal_",
    "modify_",
    "private_",
    "readonly_",
    "remove_",
    "run_",
    "symlink_",
)


def list_repository_only_entries():
    # chezmoi skips source entries whose names start with a dot, apart from
    # its own .chezmoi* files, so only undotted names reach the home directory.
    return sorted(
        entry.name
        for entry in DOTFILES_ROOT.iterdir()
        if not entry.name.startswith(".")
        and not entry.name.startswith(CHEZMOI_SOURCE_PREFIXES)
    )


def read_unconditional_ignore_patterns():
    unconditional_text, _, _ = CHEZMOIIGNORE.read_text().partition("{{")
    return {
        line.strip()
        for line in unconditional_text.splitlines()
        if line.strip() and not line.startswith("#")
    }


@pytest.mark.parametrize("entry_name", list_repository_only_entries())
def test_should_ignore_repository_only_entry_on_every_host(entry_name):
    assert entry_name in read_unconditional_ignore_patterns()
