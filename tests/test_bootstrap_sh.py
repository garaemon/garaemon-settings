"""Tests for bootstrap.sh.

Each test sources bootstrap.sh to call one function in isolation. Commands
with side effects (git, sudo, apt-get) are replaced by stub executables on a
private PATH, so no test touches the network or the real $HOME.
"""

import os
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
BOOTSTRAP_SH = REPO_ROOT / "bootstrap.sh"


def write_stub(stub_dir, name, body):
    """Create an executable stub named name that runs the given bash body."""
    stub_path = stub_dir / name
    stub_path.write_text(f"#!/bin/bash\n{body}\n")
    stub_path.chmod(0o755)
    return stub_path


def source_and_run(snippet, home, stub_dir=None):
    """Source bootstrap.sh with HOME set to home, then run snippet."""
    test_env = os.environ.copy()
    test_env["HOME"] = str(home)
    test_env.pop("XDG_DATA_HOME", None)
    test_env.pop("XDG_CONFIG_HOME", None)
    if stub_dir is not None:
        test_env["PATH"] = f"{stub_dir}:{test_env['PATH']}"
    full_script = f'source "{BOOTSTRAP_SH}"\n{snippet}'
    return subprocess.run(
        ["bash", "-c", full_script],
        env=test_env,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def stub_dir(tmp_path):
    directory = tmp_path / "stubs"
    directory.mkdir()
    return directory


class TestMainArguments:
    """main() argument parsing, with every step replaced by an echo."""

    HARNESS = (
        "install_prerequisites() { echo PREREQ; }\n"
        "clone_repository() { echo CLONE; }\n"
        "apply_dotfiles() { echo DOTFILES; }\n"
        "install_ansible() { echo ANSIBLE; }\n"
        'run_playbook() { echo "PLAYBOOK:$1"; }\n'
    )

    def run_main(self, args, home):
        return source_and_run(f"{self.HARNESS}main {args}", home)

    def test_should_print_usage_for_help(self, tmp_path):
        result = self.run_main("--help", tmp_path)
        assert "Usage: bootstrap.sh" in result.stdout

    def test_should_exit_zero_for_help(self, tmp_path):
        result = self.run_main("--help", tmp_path)
        assert result.returncode == 0

    def test_should_run_main_playbook_by_default(self, tmp_path):
        result = self.run_main("", tmp_path)
        assert "PLAYBOOK:main" in result.stdout

    def test_should_run_every_step_in_order(self, tmp_path):
        result = self.run_main("", tmp_path)
        steps = [
            line for line in result.stdout.splitlines()
            if not line.startswith("[bootstrap]")
        ]
        assert steps == [
            "PREREQ", "CLONE", "DOTFILES", "ANSIBLE", "PLAYBOOK:main",
        ]

    def test_should_accept_minimal_playbook(self, tmp_path):
        result = self.run_main("--playbook minimal", tmp_path)
        assert "PLAYBOOK:minimal" in result.stdout

    def test_should_accept_playbook_with_equals(self, tmp_path):
        result = self.run_main("--playbook=ax8-max", tmp_path)
        assert "PLAYBOOK:ax8-max" in result.stdout

    def test_should_exit_2_for_unknown_playbook(self, tmp_path):
        result = self.run_main("--playbook bogus", tmp_path)
        assert result.returncode == 2

    def test_should_exit_2_for_unknown_argument(self, tmp_path):
        result = self.run_main("--nope", tmp_path)
        assert result.returncode == 2

    def test_should_skip_ansible_when_requested(self, tmp_path):
        result = self.run_main("--skip-ansible", tmp_path)
        assert "ANSIBLE" not in result.stdout

    def test_should_skip_playbook_when_ansible_skipped(self, tmp_path):
        result = self.run_main("--skip-ansible", tmp_path)
        assert "PLAYBOOK" not in result.stdout

    def test_should_skip_dotfiles_when_requested(self, tmp_path):
        result = self.run_main("--skip-dotfiles", tmp_path)
        assert "DOTFILES" not in result.stdout


class TestCloneRepository:
    def test_should_skip_clone_when_checkout_exists(self, tmp_path, stub_dir):
        checkout = tmp_path / "ghq/github.com/garaemon/garaemon-settings"
        (checkout / ".git").mkdir(parents=True)
        write_stub(stub_dir, "git", "echo GIT_CALLED; exit 1")
        result = source_and_run("clone_repository", tmp_path, stub_dir)
        assert "GIT_CALLED" not in result.stdout

    def test_should_clone_into_ghq_path(self, tmp_path, stub_dir):
        write_stub(stub_dir, "git", 'echo "GIT $*"')
        result = source_and_run("clone_repository", tmp_path, stub_dir)
        expected_destination = (
            f"{tmp_path}/ghq/github.com/garaemon/garaemon-settings"
        )
        assert (
            "GIT clone https://github.com/garaemon/garaemon-settings.git "
            f"{expected_destination}"
        ) in result.stdout


class TestConfigureChezmoiSource:
    SOURCE_DIR_LINE = (
        'sourceDir = "~/ghq/github.com/garaemon/garaemon-settings"'
    )

    def chezmoi_toml(self, home):
        return home / ".config/chezmoi/chezmoi.toml"

    def test_should_create_config_when_missing(self, tmp_path):
        source_and_run("configure_chezmoi_source", tmp_path)
        content = self.chezmoi_toml(tmp_path).read_text()
        assert content.strip() == self.SOURCE_DIR_LINE

    def test_should_prepend_source_dir_above_tables(self, tmp_path):
        config = self.chezmoi_toml(tmp_path)
        config.parent.mkdir(parents=True)
        config.write_text('[data.atuin]\n  syncAddress = "https://x"\n')
        source_and_run("configure_chezmoi_source", tmp_path)
        first_line = config.read_text().splitlines()[0]
        assert first_line == self.SOURCE_DIR_LINE

    def test_should_keep_existing_tables(self, tmp_path):
        config = self.chezmoi_toml(tmp_path)
        config.parent.mkdir(parents=True)
        config.write_text('[data.atuin]\n  syncAddress = "https://x"\n')
        source_and_run("configure_chezmoi_source", tmp_path)
        assert "[data.atuin]" in config.read_text()

    def test_should_leave_existing_source_dir_alone(self, tmp_path):
        config = self.chezmoi_toml(tmp_path)
        config.parent.mkdir(parents=True)
        original = 'sourceDir = "~/elsewhere"\n'
        config.write_text(original)
        source_and_run("configure_chezmoi_source", tmp_path)
        assert config.read_text() == original


class TestBuildBecomeArguments:
    def test_should_ask_password_when_sudo_needs_one(self, tmp_path, stub_dir):
        write_stub(stub_dir, "sudo", "exit 1")
        result = source_and_run("build_become_arguments", tmp_path, stub_dir)
        assert result.stdout.strip() == "--ask-become-pass"

    def test_should_not_ask_password_for_passwordless_sudo(
        self, tmp_path, stub_dir
    ):
        write_stub(stub_dir, "sudo", "exit 0")
        result = source_and_run("build_become_arguments", tmp_path, stub_dir)
        assert result.stdout.strip() == ""
