"""Tests for the print-rockman zsh function in dot_zsh/rockman.zsh.

The function draws a pixel-art sprite with half-block characters, so each
terminal line packs two sprite rows.
"""

import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
ROCKMAN_ZSH = REPO_ROOT / "dot_zsh" / "rockman.zsh"
SPRITE_HEIGHT = 26
SPRITE_WIDTH = 20
ANSI_ESCAPE_PATTERN = re.compile(r"\x1b\[[0-9;]*m")


def run_print_rockman():
    return subprocess.run(
        ["zsh", "-c", f"source {ROCKMAN_ZSH} && print-rockman"],
        capture_output=True,
        text=True,
        check=True,
    )


def strip_ansi(text):
    return ANSI_ESCAPE_PATTERN.sub("", text)


def test_should_print_half_as_many_lines_as_sprite_rows():
    output = run_print_rockman().stdout

    assert len(output.splitlines()) == SPRITE_HEIGHT // 2


def test_should_print_sprite_width_cells_per_line():
    lines = strip_ansi(run_print_rockman().stdout).splitlines()

    assert all(len(line) == SPRITE_WIDTH for line in lines)


def test_should_reset_colors_at_end_of_every_line():
    lines = run_print_rockman().stdout.splitlines()

    assert all(line.endswith("\x1b[0m") for line in lines)

