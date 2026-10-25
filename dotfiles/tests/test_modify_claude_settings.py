"""Check that the chezmoi modify template for ~/.claude/settings.json enables
the i-have-adhd plugin without clobbering the rest of the file.

Claude Code itself writes permissions and plugin state into settings.json, so
chezmoi must merge into the existing file instead of replacing it.

Each test runs `chezmoi apply` with only chezmoi on PATH. bootstrap.sh applies
the dotfiles before mise installs jq and friends, so the merge must not call
any external command.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest


DOTFILES_DIR = Path(__file__).resolve().parent.parent
SETTINGS_RELATIVE_PATH = Path(".claude") / "settings.json"
PLUGIN_ID = "i-have-adhd@i-have-adhd"
MARKETPLACE_NAME = "i-have-adhd"
MARKETPLACE_REPO = "ayghri/i-have-adhd"

CHEZMOI_PATH = shutil.which("chezmoi")

pytestmark = pytest.mark.skipif(
    CHEZMOI_PATH is None, reason="applying the template needs chezmoi"
)


def run_chezmoi_apply(tmp_path, existing_settings_text):
    """Applies the template to a scratch home and returns the process and path.

    Pass None to leave settings.json absent, as on a fresh machine.
    """
    home_dir = tmp_path / "home"
    settings_path = home_dir / SETTINGS_RELATIVE_PATH
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    if existing_settings_text is not None:
        settings_path.write_text(existing_settings_text)
    completed_process = subprocess.run(
        [
            CHEZMOI_PATH,
            "apply",
            "--no-tty",
            f"--source={DOTFILES_DIR}",
            f"--destination={home_dir}",
            f"--cache={tmp_path / 'cache'}",
            str(settings_path),
        ],
        env={"HOME": str(home_dir), "PATH": str(Path(CHEZMOI_PATH).parent)},
        capture_output=True,
        text=True,
        check=False,
    )
    return completed_process, settings_path


@pytest.fixture
def apply_settings_template(tmp_path):
    def apply_settings(existing_settings_text):
        completed_process, settings_path = run_chezmoi_apply(
            tmp_path, existing_settings_text
        )
        assert completed_process.returncode == 0, completed_process.stderr
        return json.loads(settings_path.read_text())

    return apply_settings


def test_should_enable_plugin_when_settings_are_empty(apply_settings_template):
    merged = apply_settings_template("")

    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_enable_plugin_when_settings_file_is_missing(apply_settings_template):
    merged = apply_settings_template(None)

    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_enable_plugin_when_settings_are_whitespace(apply_settings_template):
    merged = apply_settings_template("\n  \n")

    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_register_marketplace_when_settings_are_empty(apply_settings_template):
    merged = apply_settings_template("")

    source = merged["extraKnownMarketplaces"][MARKETPLACE_NAME]["source"]
    assert source == {"source": "github", "repo": MARKETPLACE_REPO}


def test_should_keep_unrelated_keys_when_settings_exist(apply_settings_template):
    existing = json.dumps({"permissions": {"allow": ["Bash(ls:*)"]}, "model": "opus"})

    merged = apply_settings_template(existing)

    assert merged["permissions"] == {"allow": ["Bash(ls:*)"]}
    assert merged["model"] == "opus"


def test_should_keep_other_plugins_when_settings_exist(apply_settings_template):
    existing = json.dumps({"enabledPlugins": {"other@market": True}})

    merged = apply_settings_template(existing)

    assert merged["enabledPlugins"]["other@market"] is True
    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_be_idempotent_when_applied_twice(apply_settings_template):
    once = apply_settings_template("")

    twice = apply_settings_template(json.dumps(once))

    assert twice == once


def test_should_keep_settings_untouched_when_json_is_malformed(tmp_path):
    malformed_settings = '{"model": "opus",'

    _, settings_path = run_chezmoi_apply(tmp_path, malformed_settings)

    assert settings_path.read_text() == malformed_settings


def test_should_fail_when_json_is_malformed(tmp_path):
    completed_process, _ = run_chezmoi_apply(tmp_path, '{"model": "opus",')

    assert completed_process.returncode != 0
