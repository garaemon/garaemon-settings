"""Check the chezmoi script that installs mise tools after `chezmoi apply`.

chezmoi reruns a run_onchange_after script only when its rendered contents
change, so the script embeds a hash of the mise config. Without that hash an
edited config.toml, such as a new tool or a bumped chezmoi pin, would never
reach the installed tools.
"""

import re
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
INSTALL_SCRIPT = (
    DOTFILES_ROOT / ".chezmoiscripts" / "run_onchange_after_install-mise-tools.sh.tmpl"
)


def read_install_script():
    return INSTALL_SCRIPT.read_text()


def test_should_place_install_script_under_chezmoiscripts():
    assert INSTALL_SCRIPT.is_file()


def test_should_start_install_script_with_strict_mode():
    lines = read_install_script().splitlines()
    assert lines[:2] == ["#!/bin/bash", "set -euo pipefail"]


def test_should_embed_hash_of_mise_config():
    assert (
        'include "dot_config/mise/config.toml" | sha256sum' in read_install_script()
    )


def test_should_skip_when_mise_is_missing():
    assert "command -v mise" in read_install_script()


def test_should_skip_when_destination_is_not_the_login_home():
    assert re.search(
        r'\[ "\{\{ \.chezmoi\.destDir \}\}" != "\$\{login_home\}" \]',
        read_install_script(),
    )


def test_should_install_tools_without_prompting():
    assert re.search(r"^mise install --yes$", read_install_script(), re.MULTILINE)
