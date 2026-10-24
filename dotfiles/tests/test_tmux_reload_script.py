"""Check the chezmoi script that reloads tmux after `chezmoi apply`.

chezmoi reruns a run_onchange_after script only when its rendered contents
change, so the script embeds a hash of dot_tmux.conf. Without that hash an
edited tmux.conf would never reach the running tmux server.
"""

import re
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
RELOAD_SCRIPT = (
    DOTFILES_ROOT / ".chezmoiscripts" / "run_onchange_after_reload-tmux-config.sh.tmpl"
)


def read_reload_script():
    return RELOAD_SCRIPT.read_text()


def test_should_place_reload_script_under_chezmoiscripts():
    assert RELOAD_SCRIPT.is_file()


def test_should_start_reload_script_with_strict_mode():
    lines = read_reload_script().splitlines()
    assert lines[:2] == ["#!/bin/bash", "set -euo pipefail"]


def test_should_embed_hash_of_tmux_conf():
    assert 'include "dot_tmux.conf" | sha256sum' in read_reload_script()


def test_should_skip_when_no_tmux_server_runs():
    assert "tmux list-sessions" in read_reload_script()


def test_should_skip_when_destination_is_not_the_login_home():
    assert re.search(
        r'\[ "\{\{ \.chezmoi\.destDir \}\}" != "\$\{login_home\}" \]',
        read_reload_script(),
    )


def test_should_source_tmux_conf():
    assert re.search(r"^tmux source-file ", read_reload_script(), re.MULTILINE)
