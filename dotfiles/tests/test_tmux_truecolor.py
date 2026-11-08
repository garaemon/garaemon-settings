"""Check that dot_tmux.conf carries 24-bit color through tmux.

Emacs on a terminal frame switches to 24-bit color only when COLORTERM is
truecolor, and an SSH session does not forward COLORTERM. tmux also
downsamples 24-bit colors to 256 unless the outer terminal has the RGB
feature. Either gap turns the hex colors in my-tty-faces.el into the nearest
256-color entries.
"""

import shutil
import subprocess
import uuid
from pathlib import Path

import pytest


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
TMUX_CONF = DOTFILES_ROOT / "dot_tmux.conf"

pytestmark = pytest.mark.skipif(
    shutil.which("tmux") is None, reason="tmux is not installed"
)


@pytest.fixture(name="run_tmux_command")
def fixture_run_tmux_command(tmp_path):
    """Yield a function that runs a tmux command on a server loaded with dot_tmux.conf."""
    # A fake tpm directory keeps the config from cloning tpm from GitHub.
    (tmp_path / ".tmux" / "plugins" / "tpm").mkdir(parents=True)
    socket_name = f"pytest-{uuid.uuid4().hex}"
    tmux_env = {"HOME": str(tmp_path), "PATH": "/usr/bin:/bin:/usr/local/bin"}
    base_command = ["tmux", "-L", socket_name, "-f", str(TMUX_CONF)]
    subprocess.run(
        [*base_command, "new-session", "-d", "-s", "test", "sleep 30"],
        env=tmux_env,
        check=True,
    )

    def run_tmux_command(*arguments):
        completed = subprocess.run(
            [*base_command, *arguments],
            env=tmux_env,
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout

    yield run_tmux_command
    subprocess.run([*base_command, "kill-server"], env=tmux_env, check=False)


def test_should_advertise_truecolor_to_panes(run_tmux_command):
    assert run_tmux_command("show-environment", "-g", "COLORTERM").strip() == (
        "COLORTERM=truecolor"
    )


def test_should_enable_rgb_for_xterm_clients(run_tmux_command):
    terminal_features = run_tmux_command("show-options", "-g", "terminal-features")
    assert "xterm*:RGB" in terminal_features
