"""Keep the Slack digest systemd --user units under dot_config/systemd/user
runnable.

chezmoi installs the units on ax8-max but no longer enables them, because the
digests now run as Claude Code on the web routines. The units stay so that a
timer can be enabled again by hand.
"""

import re
from pathlib import Path

import pytest


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
MONOREPO_ROOT = DOTFILES_ROOT.parent
MONOREPO_PREFIX = "ghq/github.com/garaemon/garaemon-settings/"
UNIT_DIR = DOTFILES_ROOT / "dot_config" / "systemd" / "user"
CHEZMOIIGNORE = DOTFILES_ROOT / ".chezmoiignore.tmpl"
SKILLS_SYMLINK_TEMPLATE = DOTFILES_ROOT / "dot_claude" / "symlink_skills.tmpl"
# chezmoi strips the domain suffix, so the ax8-max.local box reports "ax8-max".
DIGEST_HOST = "ax8-max"
SLACK_TIMER_NAMES = [
    "artist-live-digest-slack.timer",
    "news-digest-slack.timer",
    "spotify-daily-digest-slack.timer",
]


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


def read_non_digest_host_ignore_block():
    """Return the .chezmoiignore body that applies to every host but the one
    carrying the Slack digest units, or None when the guard is missing.
    """
    match = re.search(
        rf'{{{{ if ne \.chezmoi\.hostname "{DIGEST_HOST}" }}}}(.*?){{{{ end }}}}',
        CHEZMOIIGNORE.read_text(),
        re.DOTALL,
    )
    return match.group(1) if match else None


def test_should_ignore_units_off_the_digest_host():
    assert "dot_config/systemd" in (read_non_digest_host_ignore_block() or "")
