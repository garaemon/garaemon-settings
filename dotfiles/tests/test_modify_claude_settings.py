"""Check that the chezmoi modify script for ~/.claude/settings.json enables
the i-have-adhd plugin without clobbering the rest of the file.

Claude Code itself writes permissions and plugin state into settings.json, so
chezmoi must merge into the existing file instead of replacing it.
"""

import json
import shutil
import subprocess
from pathlib import Path

import pytest


MODIFY_SCRIPT = (
    Path(__file__).resolve().parent.parent / "dot_claude" / "modify_settings.json"
)
PLUGIN_ID = "i-have-adhd@i-have-adhd"
MARKETPLACE_NAME = "i-have-adhd"
MARKETPLACE_REPO = "ayghri/i-have-adhd"

pytestmark = pytest.mark.skipif(
    shutil.which("jq") is None, reason="the modify script needs jq"
)


def run_modify_script(existing_settings_text):
    result = subprocess.run(
        ["bash", str(MODIFY_SCRIPT)],
        input=existing_settings_text,
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def test_should_enable_plugin_when_settings_are_empty():
    merged = run_modify_script("")

    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_register_marketplace_when_settings_are_empty():
    merged = run_modify_script("")

    source = merged["extraKnownMarketplaces"][MARKETPLACE_NAME]["source"]
    assert source == {"source": "github", "repo": MARKETPLACE_REPO}


def test_should_keep_unrelated_keys_when_settings_exist():
    existing = json.dumps({"permissions": {"allow": ["Bash(ls:*)"]}, "model": "opus"})

    merged = run_modify_script(existing)

    assert merged["permissions"] == {"allow": ["Bash(ls:*)"]}
    assert merged["model"] == "opus"


def test_should_keep_other_plugins_when_settings_exist():
    existing = json.dumps({"enabledPlugins": {"other@market": True}})

    merged = run_modify_script(existing)

    assert merged["enabledPlugins"]["other@market"] is True
    assert merged["enabledPlugins"][PLUGIN_ID] is True


def test_should_be_idempotent_when_applied_twice():
    once = run_modify_script("")

    twice = run_modify_script(json.dumps(once))

    assert twice == once
