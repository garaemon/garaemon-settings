"""Keep the Slack digest systemd --user units and the chezmoi script that
enables them in sync.

The units live under dot_config/systemd/user and are enabled by a
run_onchange_after script. chezmoi reruns that script only when its rendered
contents change, so the script embeds a hash of every unit file. These tests
fail when a unit is added without wiring it into the script.
"""

import re
from pathlib import Path

import pytest


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
MONOREPO_ROOT = DOTFILES_ROOT.parent
MONOREPO_PREFIX = "ghq/github.com/garaemon/garaemon-settings/"
UNIT_DIR = DOTFILES_ROOT / "dot_config" / "systemd" / "user"
ENABLE_SCRIPT = (
    DOTFILES_ROOT
    / ".chezmoiscripts"
    / "run_onchange_after_enable-slack-digest-timers.sh.tmpl"
)
CHEZMOIIGNORE = DOTFILES_ROOT / ".chezmoiignore.tmpl"
SKILLS_SYMLINK_TEMPLATE = DOTFILES_ROOT / "dot_claude" / "symlink_skills.tmpl"
# chezmoi strips the domain suffix, so the ax8-max.local box reports "ax8-max".
DIGEST_HOST = "ax8-max"
SLACK_TIMER_NAMES = [
    "artist-live-digest-slack.timer",
    "news-digest-slack.timer",
    "spotify-daily-digest-slack.timer",
]


def list_unit_files():
    return sorted(UNIT_DIR.glob("*.service")) + sorted(UNIT_DIR.glob("*.timer"))


def read_enable_script():
    return ENABLE_SCRIPT.read_text()


@pytest.mark.parametrize("timer_name", SLACK_TIMER_NAMES)
def test_should_ship_timer_unit(timer_name):
    assert (UNIT_DIR / timer_name).is_file()


@pytest.mark.parametrize("timer_name", SLACK_TIMER_NAMES)
def test_should_ship_service_for_each_timer(timer_name):
    service_name = timer_name.replace(".timer", ".service")
    assert (UNIT_DIR / service_name).is_file()


@pytest.mark.parametrize("timer_name", SLACK_TIMER_NAMES)
def test_should_point_service_at_monorepo_wrapper_script(timer_name):
    service_text = (UNIT_DIR / timer_name.replace(".timer", ".service")).read_text()
    match = re.search(r"^ExecStart=%h/(.+)$", service_text, re.MULTILINE)
    assert match, "ExecStart must start with %h so the unit works on any machine"
    wrapper_relative_to_home = match.group(1)
    assert wrapper_relative_to_home.startswith(MONOREPO_PREFIX + "claude-skills/")
    # Resolve the rest against this checkout: a prefix check alone passes a
    # unit left pointing at a script that has since been renamed or moved.
    wrapper = MONOREPO_ROOT / wrapper_relative_to_home[len(MONOREPO_PREFIX):]
    assert wrapper.is_file(), f"{wrapper_relative_to_home} is not in this checkout"


def test_should_point_claude_skills_symlink_at_the_monorepo_skills():
    target = SKILLS_SYMLINK_TEMPLATE.read_text().strip()
    _, _, relative_to_home = target.partition("}}/")
    assert relative_to_home.startswith(MONOREPO_PREFIX)
    skills_dir = MONOREPO_ROOT / relative_to_home[len(MONOREPO_PREFIX):]
    assert skills_dir.is_dir(), f"{relative_to_home} is not in this checkout"


def test_should_place_enable_script_under_chezmoiscripts():
    assert ENABLE_SCRIPT.is_file()


def test_should_start_enable_script_with_strict_mode():
    lines = read_enable_script().splitlines()
    assert lines[:2] == ["#!/bin/bash", "set -euo pipefail"]


@pytest.mark.parametrize("unit_path", list_unit_files(), ids=lambda path: path.name)
def test_should_embed_hash_of_each_unit_in_enable_script(unit_path):
    include_directive = f'include "dot_config/systemd/user/{unit_path.name}"'
    assert include_directive in read_enable_script()


@pytest.mark.parametrize("timer_name", SLACK_TIMER_NAMES)
def test_should_enable_each_timer_in_enable_script(timer_name):
    assert re.search(
        # Allow backslash-newline continuations between the timer names.
        rf"systemctl --user enable --now(?:[^\n]|\\\n)*\b{re.escape(timer_name)}\b",
        read_enable_script(),
    )


def test_should_skip_enable_script_when_no_user_systemd_session():
    assert "systemctl --user show-environment" in read_enable_script()


def read_non_digest_host_ignore_block():
    """Return the .chezmoiignore body that applies to every host but the one
    running the Slack digest timers, or None when the guard is missing.
    """
    match = re.search(
        rf'{{{{ if ne \.chezmoi\.hostname "{DIGEST_HOST}" }}}}(.*?){{{{ end }}}}',
        CHEZMOIIGNORE.read_text(),
        re.DOTALL,
    )
    return match.group(1) if match else None


def test_should_ignore_units_off_the_digest_host():
    assert "dot_config/systemd" in (read_non_digest_host_ignore_block() or "")


def test_should_ignore_enable_script_off_the_digest_host():
    assert (
        ".chezmoiscripts/run_onchange_after_enable-slack-digest-timers.sh.tmpl"
        in (read_non_digest_host_ignore_block() or "")
    )


def test_should_skip_enable_script_when_destination_is_not_the_login_home():
    assert re.search(
        r'\[ "\{\{ \.chezmoi\.destDir \}\}" != "\$\{login_home\}" \]',
        read_enable_script(),
    )
