"""Tests for tmux-gpu-status.

The script feeds the second tmux status line. A fake `nvidia-smi` on PATH
replays canned CSV output so the tests run on machines without a GPU.
"""

import os
import shlex
import subprocess
from pathlib import Path


DOTFILES_ROOT = Path(__file__).resolve().parent.parent
GPU_STATUS = DOTFILES_ROOT / "dot_local" / "bin" / "executable_tmux-gpu-status"
TMUX_CONF = DOTFILES_ROOT / "dot_tmux.conf"


def install_fake_nvidia_smi(bin_dir, csv_output, exit_status=0):
    bin_dir.mkdir(parents=True, exist_ok=True)
    nvidia_smi = bin_dir / "nvidia-smi"
    nvidia_smi.write_text(
        "#!/bin/bash\n"
        f"printf '%s' {shlex.quote(csv_output)}\n"
        f"exit {exit_status}\n"
    )
    nvidia_smi.chmod(0o755)


def run_gpu_status(fake_bin):
    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}{os.pathsep}/usr/bin{os.pathsep}/bin"
    return subprocess.run(
        ["bash", str(GPU_STATUS)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )


def test_should_print_vram_usage_of_single_gpu(tmp_path):
    install_fake_nvidia_smi(tmp_path, "0, 6144, 24576\n")
    result = run_gpu_status(tmp_path)
    assert result.stdout == "#[fg=green]GPU0 VRAM 6.0/24.0GiB (25%)#[default]\n"


def test_should_join_multiple_gpus_with_separator(tmp_path):
    install_fake_nvidia_smi(tmp_path, "0, 1024, 8192\n1, 4096, 8192\n")
    result = run_gpu_status(tmp_path)
    assert " | " in result.stdout


def test_should_color_high_usage_red(tmp_path):
    install_fake_nvidia_smi(tmp_path, "0, 7680, 8192\n")
    result = run_gpu_status(tmp_path)
    assert result.stdout.startswith("#[fg=red]")


def test_should_color_medium_usage_yellow(tmp_path):
    install_fake_nvidia_smi(tmp_path, "0, 4096, 8192\n")
    result = run_gpu_status(tmp_path)
    assert result.stdout.startswith("#[fg=yellow]")


def test_should_print_nothing_when_nvidia_smi_is_missing(tmp_path):
    result = run_gpu_status(tmp_path)
    assert (result.stdout, result.returncode) == ("", 0)


def test_should_print_nothing_when_nvidia_smi_fails(tmp_path):
    install_fake_nvidia_smi(tmp_path, "NVIDIA-SMI has failed\n", exit_status=9)
    result = run_gpu_status(tmp_path)
    assert (result.stdout, result.returncode) == ("", 0)


def test_should_enable_second_status_line_only_with_nvidia_smi():
    tmux_conf = TMUX_CONF.read_text()
    assert 'if-shell "command -v nvidia-smi' in tmux_conf


def test_should_show_gpu_status_in_second_status_line():
    tmux_conf = TMUX_CONF.read_text()
    assert "status-format[1]" in tmux_conf and "tmux-gpu-status" in tmux_conf
