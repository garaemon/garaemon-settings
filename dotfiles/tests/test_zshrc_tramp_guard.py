"""Check the TERM guard at the top of dot_zshrc.

The guard gives TRAMP's control shell a bare prompt, but a vterm opened on a
remote directory also arrives with TERM=dumb: TRAMP's direct async process
overrides TERM with `tramp-terminal-type`. The tests run only the guard,
because sourcing the whole zshrc downloads plugins.
"""

import os
import shutil
import subprocess
from pathlib import Path

import pytest


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
ZSHRC = DOTFILES_ROOT / "dot_zshrc"
GUARD_START_MARKER = "# Emacs TRAMP and vterm"
GUARD_END_MARKER = "esac"

pytestmark = pytest.mark.skipif(shutil.which("zsh") is None, reason="zsh is not installed")


def extract_term_guard():
    """Return the zshrc lines from the guard comment through its closing esac."""
    lines = ZSHRC.read_text().splitlines()
    start_index = next(
        index for index, line in enumerate(lines) if line.startswith(GUARD_START_MARKER)
    )
    end_index = next(
        index for index in range(start_index, len(lines)) if lines[index] == GUARD_END_MARKER
    )
    return "\n".join(lines[start_index : end_index + 1])


def run_guard(term, inside_emacs):
    """Return `TERM PS1` as zsh sees them after running the guard."""
    guard_function = "run_guard() {\n" + extract_term_guard() + "\n}\n"
    script = guard_function + 'run_guard\nprint -r -- "$TERM $PS1"\n'
    guard_env = {"PATH": os.environ["PATH"], "TERM": term, "PS1": "full-prompt"}
    if inside_emacs is not None:
        guard_env["INSIDE_EMACS"] = inside_emacs
    completed = subprocess.run(
        ["zsh", "-f", "-c", script],
        check=True,
        capture_output=True,
        text=True,
        env=guard_env,
    )
    return completed.stdout.strip()


def test_should_give_tramp_control_shell_bare_prompt():
    assert run_guard("dumb", None) == "dumb $"


def test_should_give_tramp_vterm_a_capable_term():
    assert run_guard("dumb", "vterm,tramp:2.8.2.31.1") == "xterm-256color full-prompt"


def test_should_keep_local_vterm_term():
    assert run_guard("xterm-256color", "vterm") == "xterm-256color full-prompt"
