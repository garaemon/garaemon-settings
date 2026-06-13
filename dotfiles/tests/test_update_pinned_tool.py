"""Tests for .github/scripts/update_pinned_tool.py.

Pure-Python tests: import the script as a module and exercise the
transformation helpers against fixtures, parameterised over both tools the
script knows about (chezmoi and mise). The network-dependent helpers
(fetch_latest_version, fetch_release_checksums) are covered indirectly via
the main() integration tests that monkeypatch them.
"""

import datetime
import importlib.util
import json
import stat
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = REPO_ROOT / ".github" / "scripts" / "update_pinned_tool.py"


def load_script_module():
    # Imported by file path because .github/scripts/ is not a Python package
    # (no __init__.py) and a hyphen would not be valid in an import name
    # anyway. spec_from_file_location is the stdlib-blessed escape hatch.
    spec = importlib.util.spec_from_file_location(
        "update_pinned_tool", SCRIPT_PATH
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules["update_pinned_tool"] = module
    spec.loader.exec_module(module)
    return module


update_tool = load_script_module()

CHEZMOI = update_tool.TOOLS["chezmoi"]
MISE = update_tool.TOOLS["mise"]


# ---------------------------------------------------------------------------
# Per-tool fixtures
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class ToolFixture:
    """A self-contained set of fixtures for one tool, so the transformation
    tests can run identically against chezmoi and mise.
    """

    spec: object
    install_sh: str
    pinned: str
    new_version: str
    checksums_txt: str
    expected: dict  # platform -> sha256 in checksums_txt for new_version
    cli_args: tuple  # extra args to select this tool in main()


CHEZMOI_FIXTURE = ToolFixture(
    spec=CHEZMOI,
    install_sh="""\
#!/usr/bin/env bash
readonly CHEZMOI_VERSION="2.70.3"

declare -rA CHEZMOI_CHECKSUMS=(
    [darwin_amd64]="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    [darwin_arm64]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    [linux_amd64]="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    [linux_arm64]="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
)
""",
    pinned="2.70.3",
    new_version="2.71.0",
    checksums_txt="""\
1111111111111111111111111111111111111111111111111111111111111111  chezmoi_2.71.0_darwin_amd64.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  chezmoi_2.71.0_darwin_arm64.tar.gz
3333333333333333333333333333333333333333333333333333333333333333  chezmoi_2.71.0_linux_amd64.tar.gz
4444444444444444444444444444444444444444444444444444444444444444  chezmoi_2.71.0_linux_arm64.tar.gz
5555555555555555555555555555555555555555555555555555555555555555  chezmoi_2.71.0_freebsd_amd64.tar.gz
""",
    expected={
        "darwin_amd64": "1" * 64,
        "darwin_arm64": "2" * 64,
        "linux_amd64": "3" * 64,
        "linux_arm64": "4" * 64,
    },
    cli_args=(),
)

# mise uses CalVer (YYYY.M.P) tags, a single shared SHASUMS256.txt manifest
# whose filename column is prefixed with "./", and hyphenated platform keys.
MISE_FIXTURE = ToolFixture(
    spec=MISE,
    install_sh="""\
#!/usr/bin/env bash
readonly MISE_VERSION="2026.1.0"

declare -rA MISE_CHECKSUMS=(
    [linux-x64]="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    [linux-arm64]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    [macos-x64]="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    [macos-arm64]="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
)
""",
    pinned="2026.1.0",
    new_version="2026.6.6",
    checksums_txt="""\
1111111111111111111111111111111111111111111111111111111111111111  ./mise-v2026.6.6-linux-x64.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  ./mise-v2026.6.6-linux-arm64.tar.gz
3333333333333333333333333333333333333333333333333333333333333333  ./mise-v2026.6.6-macos-x64.tar.gz
4444444444444444444444444444444444444444444444444444444444444444  ./mise-v2026.6.6-macos-arm64.tar.gz
5555555555555555555555555555555555555555555555555555555555555555  ./mise-v2026.6.6-linux-x64-musl.tar.gz
""",
    expected={
        "linux-x64": "1" * 64,
        "linux-arm64": "2" * 64,
        "macos-x64": "3" * 64,
        "macos-arm64": "4" * 64,
    },
    cli_args=("--tool", "mise"),
)

ALL_FIXTURES = [CHEZMOI_FIXTURE, MISE_FIXTURE]


def _fixture_id(fx):
    return fx.spec.name


both_tools = pytest.mark.parametrize("fx", ALL_FIXTURES, ids=_fixture_id)


# ---------------------------------------------------------------------------
# ToolSpec helpers
# ---------------------------------------------------------------------------
class TestToolSpec:
    def test_chezmoi_checksums_url(self):
        assert CHEZMOI.checksums_url("2.71.0") == (
            "https://github.com/twpayne/chezmoi/releases/download/"
            "v2.71.0/chezmoi_2.71.0_checksums.txt"
        )

    def test_mise_checksums_url(self):
        assert MISE.checksums_url("2026.6.6") == (
            "https://github.com/jdx/mise/releases/download/"
            "v2026.6.6/SHASUMS256.txt"
        )

    def test_chezmoi_asset_name(self):
        assert (
            CHEZMOI.asset_name("2.71.0", "linux_amd64")
            == "chezmoi_2.71.0_linux_amd64.tar.gz"
        )

    def test_mise_asset_name(self):
        assert (
            MISE.asset_name("2026.6.6", "linux-x64")
            == "mise-v2026.6.6-linux-x64.tar.gz"
        )


# ---------------------------------------------------------------------------
# Release.from_payload
# ---------------------------------------------------------------------------
class TestReleaseFromPayload:
    def test_maps_known_fields(self):
        release = update_tool.Release.from_payload(
            {
                "tag_name": "v2.72.0",
                "published_at": "2026-05-01T00:00:00Z",
                "draft": False,
                "prerelease": True,
            }
        )
        assert release == update_tool.Release(
            tag_name="v2.72.0",
            published_at="2026-05-01T00:00:00Z",
            draft=False,
            prerelease=True,
        )

    def test_defaults_missing_fields(self):
        release = update_tool.Release.from_payload({"tag_name": "v2.72.0"})
        assert release.published_at is None
        assert release.draft is False
        assert release.prerelease is False

    def test_defaults_empty_tag_when_absent(self):
        release = update_tool.Release.from_payload({})
        assert release.tag_name == ""


# ---------------------------------------------------------------------------
# fetch_releases_payload
# ---------------------------------------------------------------------------
class TestFetchReleasesPayload:
    def _patch_response(self, monkeypatch, body):
        monkeypatch.setattr(
            update_tool,
            "open_github_url",
            lambda *args, **kwargs: FakeResponse(body),
        )

    def test_returns_list_of_release_dataclasses(self, monkeypatch):
        body = json.dumps(
            [
                {
                    "tag_name": "v2.72.0",
                    "published_at": "2026-05-01T00:00:00Z",
                    "draft": False,
                    "prerelease": False,
                }
            ]
        ).encode("utf-8")
        self._patch_response(monkeypatch, body)
        releases = update_tool.fetch_releases_payload("owner/repo")
        assert releases == [
            update_tool.Release(
                tag_name="v2.72.0",
                published_at="2026-05-01T00:00:00Z",
                draft=False,
                prerelease=False,
            )
        ]

    def test_raises_on_malformed_json(self, monkeypatch):
        self._patch_response(monkeypatch, b"<html>incident</html>")
        with pytest.raises(update_tool.UpdateError, match="malformed"):
            update_tool.fetch_releases_payload("owner/repo")

    def test_raises_when_payload_is_not_a_list(self, monkeypatch):
        body = json.dumps({"message": "Not Found"}).encode("utf-8")
        self._patch_response(monkeypatch, body)
        with pytest.raises(update_tool.UpdateError, match="array"):
            update_tool.fetch_releases_payload("owner/repo")


# ---------------------------------------------------------------------------
# select_latest_eligible_release
# ---------------------------------------------------------------------------
NOW = datetime.datetime(2026, 5, 9, 12, 0, tzinfo=datetime.UTC)


def make_release(tag, days_ago, *, draft=False, prerelease=False):
    """Build a Release shaped like one GitHub /releases payload entry."""
    published = NOW - datetime.timedelta(days=days_ago)
    # GitHub serialises the trailing UTC offset as ``Z``; Python's
    # datetime.isoformat() emits ``+00:00``. Mimic the GitHub form so
    # parse_published_at exercises the same input shape it sees in prod.
    published_at = published.isoformat().replace("+00:00", "Z")
    return update_tool.Release(
        tag_name=tag,
        published_at=published_at,
        draft=draft,
        prerelease=prerelease,
    )


class TestSelectLatestEligibleRelease:
    def test_returns_first_old_enough_release_in_list_order(self):
        # The GitHub /releases endpoint returns entries in reverse-creation
        # order (newest first), so picking the first eligible entry == pick
        # the newest stable release that has aged at least min_age_days.
        releases = [
            make_release("v2.72.0", days_ago=2),
            make_release("v2.71.0", days_ago=10),
            make_release("v2.70.3", days_ago=40),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"

    def test_selects_calver_tag_for_mise(self):
        # mise tags look like v2026.6.6; the strict MAJOR.MINOR.PATCH pattern
        # accepts them and "newest aged-enough" still works.
        releases = [
            make_release("v2026.6.20", days_ago=2),
            make_release("v2026.6.6", days_ago=9),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2026.6.6"

    def test_skips_drafts_and_prereleases(self):
        releases = [
            make_release("v2.72.0", days_ago=14, draft=True),
            make_release("v2.72.0-rc.1", days_ago=10, prerelease=True),
            make_release("v2.71.0", days_ago=8),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"

    def test_accepts_release_exactly_at_cutoff(self):
        releases = [make_release("v2.71.0", days_ago=7)]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"

    def test_raises_when_nothing_old_enough(self):
        releases = [
            make_release("v2.72.0", days_ago=1),
            make_release("v2.71.0", days_ago=3),
        ]
        with pytest.raises(update_tool.UpdateError, match="older than"):
            update_tool.select_latest_eligible_release(releases, now=NOW)

    def test_raises_on_empty_release_list(self):
        with pytest.raises(update_tool.UpdateError, match="0 candidates"):
            update_tool.select_latest_eligible_release([], now=NOW)

    def test_skips_release_missing_published_at(self):
        releases = [
            update_tool.Release(
                tag_name="v2.72.0",
                published_at=None,
                draft=False,
                prerelease=False,
            ),
            make_release("v2.71.0", days_ago=8),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"

    def test_honors_custom_min_age_days(self):
        releases = [make_release("v2.72.0", days_ago=14)]
        with pytest.raises(update_tool.UpdateError):
            update_tool.select_latest_eligible_release(
                releases, now=NOW, min_age_days=30
            )

    def test_skips_release_with_non_version_tag(self):
        releases = [
            make_release("nightly", days_ago=14),
            make_release("v2.71.0", days_ago=10),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"

    def test_skips_tag_with_path_traversal_chars(self):
        releases = [
            make_release("../../etc/passwd", days_ago=14),
            make_release("v2.71.0", days_ago=10),
        ]
        result = update_tool.select_latest_eligible_release(releases, now=NOW)
        assert result == "2.71.0"


# ---------------------------------------------------------------------------
# parse_version_tuple
# ---------------------------------------------------------------------------
class TestParseVersionTuple:
    def test_returns_tuple_for_strict_semver(self):
        assert update_tool.parse_version_tuple("2.71.0") == (2, 71, 0)

    def test_returns_tuple_for_calver(self):
        assert update_tool.parse_version_tuple("2026.6.6") == (2026, 6, 6)

    def test_raises_on_non_numeric_component(self):
        with pytest.raises(update_tool.UpdateError, match="MAJOR.MINOR.PATCH"):
            update_tool.parse_version_tuple("2.71.x")

    def test_raises_on_wrong_arity(self):
        with pytest.raises(update_tool.UpdateError, match="MAJOR.MINOR.PATCH"):
            update_tool.parse_version_tuple("2.71")

    def test_raises_on_empty_string(self):
        with pytest.raises(update_tool.UpdateError, match="MAJOR.MINOR.PATCH"):
            update_tool.parse_version_tuple("")


# ---------------------------------------------------------------------------
# read_pinned_version
# ---------------------------------------------------------------------------
class TestReadPinnedVersion:
    @both_tools
    def test_returns_version_from_install_sh(self, fx, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        assert (
            update_tool.read_pinned_version(install_sh, fx.spec) == fx.pinned
        )

    @both_tools
    def test_raises_when_version_marker_absent(self, fx, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text("#!/usr/bin/env bash\necho hi\n")
        with pytest.raises(update_tool.UpdateError, match=fx.spec.version_var):
            update_tool.read_pinned_version(install_sh, fx.spec)


# ---------------------------------------------------------------------------
# extract_platform_checksum
# ---------------------------------------------------------------------------
class TestExtractPlatformChecksum:
    @both_tools
    def test_returns_sha_for_known_platform(self, fx):
        for platform, expected_sha in fx.expected.items():
            sha = update_tool.extract_platform_checksum(
                fx.checksums_txt, fx.new_version, platform, fx.spec
            )
            assert sha == expected_sha

    @both_tools
    def test_raises_for_missing_platform(self, fx):
        with pytest.raises(update_tool.UpdateError, match="windows_x64"):
            update_tool.extract_platform_checksum(
                fx.checksums_txt, fx.new_version, "windows_x64", fx.spec
            )


# ---------------------------------------------------------------------------
# apply_update
# ---------------------------------------------------------------------------
class TestApplyUpdate:
    @both_tools
    def test_rewrites_version_and_all_checksums(self, fx, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        update_tool.apply_update(
            install_sh, fx.new_version, fx.checksums_txt, fx.spec
        )
        rewritten = install_sh.read_text()
        assert f'{fx.spec.version_var}="{fx.new_version}"' in rewritten
        for platform, sha in fx.expected.items():
            assert f'[{platform}]="{sha}"' in rewritten
        # Lines unrelated to checksums must be preserved verbatim.
        assert f"declare -rA {fx.spec.checksums_array}=(" in rewritten

    @both_tools
    def test_preserves_executable_bit(self, fx, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        install_sh.chmod(0o755)
        update_tool.apply_update(
            install_sh, fx.new_version, fx.checksums_txt, fx.spec
        )
        mode = install_sh.stat().st_mode
        assert mode & stat.S_IXUSR, f"executable bit dropped: {oct(mode)}"

    def test_cleans_up_tmp_file_when_replace_fails(
        self, tmp_path, monkeypatch
    ):
        fx = CHEZMOI_FIXTURE
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        original = install_sh.read_text()

        def boom_replace(_src, _dst):
            raise OSError("simulated rename failure")

        monkeypatch.setattr(update_tool.os, "replace", boom_replace)
        with pytest.raises(OSError, match="simulated rename failure"):
            update_tool.apply_update(
                install_sh, fx.new_version, fx.checksums_txt, fx.spec
            )
        # tmp file must not linger after the failure.
        leftovers = list(tmp_path.glob("install.sh*.tmp"))
        assert leftovers == []
        # install.sh on disk must not have been clobbered.
        assert install_sh.read_text() == original

    @both_tools
    def test_is_idempotent_when_target_version_already_pinned(
        self, fx, tmp_path
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        update_tool.apply_update(
            install_sh, fx.new_version, fx.checksums_txt, fx.spec
        )
        snapshot = install_sh.read_text()
        update_tool.apply_update(
            install_sh, fx.new_version, fx.checksums_txt, fx.spec
        )
        assert install_sh.read_text() == snapshot

    @both_tools
    def test_aborts_when_platform_missing_from_checksums(self, fx, tmp_path):
        # Drop the last platform's line from the manifest.
        missing = list(fx.expected)[-1]
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        partial_text = "\n".join(
            line
            for line in fx.checksums_txt.splitlines()
            if missing not in line
        ) + "\n"
        with pytest.raises(update_tool.UpdateError, match=missing):
            update_tool.apply_update(
                install_sh, fx.new_version, partial_text, fx.spec
            )
        # File on disk was not modified because validation runs first.
        assert install_sh.read_text() == fx.install_sh

    @both_tools
    def test_aborts_when_version_marker_missing_from_install_sh(
        self, fx, tmp_path
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(
            fx.install_sh.replace(
                f'readonly {fx.spec.version_var}="{fx.pinned}"',
                f'VER="{fx.pinned}"',
            )
        )
        original = install_sh.read_text()
        with pytest.raises(update_tool.UpdateError, match=fx.spec.version_var):
            update_tool.apply_update(
                install_sh, fx.new_version, fx.checksums_txt, fx.spec
            )
        assert install_sh.read_text() == original

    @both_tools
    def test_aborts_when_platform_key_missing_from_install_sh(
        self, fx, tmp_path
    ):
        # Drop one platform's array entry so the regex cannot find a place to
        # put the new sha256.
        missing = list(fx.expected)[-1]
        install_sh = tmp_path / "install.sh"
        damaged = "\n".join(
            line
            for line in fx.install_sh.splitlines()
            if f"[{missing}]" not in line
        ) + "\n"
        install_sh.write_text(damaged)
        with pytest.raises(update_tool.UpdateError, match=missing):
            update_tool.apply_update(
                install_sh, fx.new_version, fx.checksums_txt, fx.spec
            )


# ---------------------------------------------------------------------------
# main: end-to-end with monkeypatched network helpers
# ---------------------------------------------------------------------------
def fail_if_called(*_args, **_kwargs):
    """Pytest helper: substitute for a function that must not be invoked."""
    raise AssertionError("function under monkeypatch should not be called")


class TestMain:
    @both_tools
    def test_no_op_when_already_pinned_to_latest(
        self, fx, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: fx.pinned
        )
        monkeypatch.setattr(
            update_tool, "fetch_release_checksums", fail_if_called
        )
        rc = update_tool.main([*fx.cli_args, str(install_sh)])
        assert rc == 0
        assert install_sh.read_text() == fx.install_sh

    @both_tools
    def test_updates_install_sh_when_new_version_available(
        self, fx, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: fx.new_version
        )
        monkeypatch.setattr(
            update_tool,
            "fetch_release_checksums",
            lambda version, spec: fx.checksums_txt,
        )
        rc = update_tool.main([*fx.cli_args, str(install_sh)])
        assert rc == 0
        rewritten = install_sh.read_text()
        assert f'{fx.spec.version_var}="{fx.new_version}"' in rewritten
        last_platform = list(fx.expected)[-1]
        assert f'[{last_platform}]="{fx.expected[last_platform]}"' in rewritten

    @both_tools
    def test_refuses_downgrade(self, fx, tmp_path, monkeypatch):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        # Pretend upstream's latest eligible is older than what is pinned by
        # decrementing the major component.
        older = fx.pinned.split(".")
        older[0] = str(int(older[0]) - 1)
        older_version = ".".join(older)
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: older_version
        )
        monkeypatch.setattr(
            update_tool, "fetch_release_checksums", fail_if_called
        )
        with pytest.raises(update_tool.UpdateError, match="downgrade"):
            update_tool.main([*fx.cli_args, str(install_sh)])
        assert install_sh.read_text() == fx.install_sh

    @both_tools
    def test_writes_github_output_when_changed(
        self, fx, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        github_output = tmp_path / "github_output.txt"
        monkeypatch.setenv("GITHUB_OUTPUT", str(github_output))
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: fx.new_version
        )
        monkeypatch.setattr(
            update_tool,
            "fetch_release_checksums",
            lambda version, spec: fx.checksums_txt,
        )
        update_tool.main([*fx.cli_args, str(install_sh)])
        contents = github_output.read_text().splitlines()
        assert "changed=true" in contents
        assert f"version={fx.new_version}" in contents

    @both_tools
    def test_writes_github_output_when_unchanged(
        self, fx, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        github_output = tmp_path / "github_output.txt"
        monkeypatch.setenv("GITHUB_OUTPUT", str(github_output))
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: fx.pinned
        )
        monkeypatch.setattr(
            update_tool, "fetch_release_checksums", fail_if_called
        )
        update_tool.main([*fx.cli_args, str(install_sh)])
        contents = github_output.read_text().splitlines()
        assert "changed=false" in contents
        assert f"version={fx.pinned}" in contents

    def test_skips_github_output_when_env_unset(self, tmp_path, monkeypatch):
        fx = CHEZMOI_FIXTURE
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(fx.install_sh)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_tool, "fetch_latest_version", lambda spec: fx.pinned
        )
        monkeypatch.setattr(
            update_tool, "fetch_release_checksums", fail_if_called
        )
        # Must not raise; the helper is a no-op outside GitHub Actions.
        rc = update_tool.main([*fx.cli_args, str(install_sh)])
        assert rc == 0

    def test_returns_nonzero_when_install_sh_missing(self, tmp_path, capsys):
        missing = tmp_path / "does-not-exist.sh"
        rc = update_tool.main([str(missing)])
        assert rc == 1
        captured = capsys.readouterr()
        assert "not found" in captured.err

    def test_defaults_to_chezmoi_when_tool_unspecified(
        self, tmp_path, monkeypatch
    ):
        # No --tool flag must select chezmoi, preserving the original CLI.
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(CHEZMOI_FIXTURE.install_sh)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        captured = {}

        def record_repo(spec):
            captured["repo"] = spec.repo
            return CHEZMOI_FIXTURE.pinned

        monkeypatch.setattr(update_tool, "fetch_latest_version", record_repo)
        monkeypatch.setattr(
            update_tool, "fetch_release_checksums", fail_if_called
        )
        rc = update_tool.main([str(install_sh)])
        assert rc == 0
        assert captured["repo"] == "twpayne/chezmoi"


# ---------------------------------------------------------------------------
# open_github_url: User-Agent and Authorization header behaviour
# ---------------------------------------------------------------------------
class FakeResponse:
    """Minimal stand-in for urllib.request.urlopen's return value."""

    def __init__(self, body=b""):
        self._body = body

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        return False

    def read(self):
        return self._body


class TestOpenGithubUrl:
    def _capture_request(self, monkeypatch):
        captured = {}

        def fake_urlopen(request, timeout=None):
            captured["request"] = request
            captured["timeout"] = timeout
            return FakeResponse()

        monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
        return captured

    def test_sets_user_agent_header(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        with update_tool.open_github_url("https://example.invalid/x"):
            pass
        # urllib normalises header names to title case (e.g. User-agent).
        headers = captured["request"].headers
        assert headers.get("User-agent") == update_tool.USER_AGENT

    def test_omits_authorization_when_no_token(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        with update_tool.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert "Authorization" not in headers

    def test_includes_bearer_when_gh_token_set(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.setenv("GH_TOKEN", "secret-test-token")
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        with update_tool.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert headers.get("Authorization") == "Bearer secret-test-token"

    def test_falls_back_to_github_token(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.setenv("GITHUB_TOKEN", "fallback-token")
        with update_tool.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert headers.get("Authorization") == "Bearer fallback-token"

    def test_omits_authorization_when_authenticated_false(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.setenv("GH_TOKEN", "secret-test-token")
        with update_tool.open_github_url(
            "https://github.com/example/releases/download/v1.0.0/asset",
            authenticated=False,
        ):
            pass
        headers = captured["request"].headers
        # Token must not travel to public download endpoints even when set.
        assert "Authorization" not in headers
        assert headers.get("User-agent") == update_tool.USER_AGENT
