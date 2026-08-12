"""Command runners shared by the branch-review scripts.

Every git call in this skill goes through here so that failures raise with the
command's own stderr attached, rather than a bare exit status. A bad revision or
a missing pull request then says why, instead of surfacing as "exit code 128".
"""

import subprocess


def run_command(args, check=True, env=None, input_text=None):
    """Run a command and return its stdout.

    Raises RuntimeError when check is true and the command fails; returns an
    empty string when check is false, so optional lookups can fall through.
    input_text, when given, is written to the command's stdin.
    """
    completed = subprocess.run(
        args, capture_output=True, text=True, env=env, input=input_text
    )
    if completed.returncode != 0:
        if not check:
            return ""
        message = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"{' '.join(args)}: {message}")
    return completed.stdout
