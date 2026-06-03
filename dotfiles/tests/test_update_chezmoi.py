"""Tests for .github/scripts/update_chezmoi.py.

Pure-Python tests: import the script as a module and exercise the
transformation helpers against fixtures. The network-dependent helpers
(fetch_latest_version, fetch_release_checksums) are covered indirectly via
the main() integration test that monkeypatches them.
"""

import datetime
import importlib.util
import json
import stat
import sys
import urllib.request
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = REPO_ROOT / ".github" / "scripts" / "update_chezmoi.py"


def load_script_module():
    # Imported by file path because .github/scripts/ is not a Python package
    # (no __init__.py) and a hyphen would not be valid in an import name
    # anyway. spec_from_file_location is the stdlib-blessed escape hatch.
    spec = importlib.util.spec_from_file_location("update_chezmoi", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules["update_chezmoi"] = module
    spec.loader.exec_module(module)
    return module


update_chezmoi = load_script_module()


FIXTURE_INSTALL_SH = """\
#!/usr/bin/env bash
readonly CHEZMOI_VERSION="2.70.3"

declare -rA CHEZMOI_CHECKSUMS=(
    [darwin_amd64]="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    [darwin_arm64]="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    [linux_amd64]="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    [linux_arm64]="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
)
"""

FIXTURE_NEW_VERSION = "2.71.0"
FIXTURE_CHECKSUMS_TXT = """\
1111111111111111111111111111111111111111111111111111111111111111  chezmoi_2.71.0_darwin_amd64.tar.gz
2222222222222222222222222222222222222222222222222222222222222222  chezmoi_2.71.0_darwin_arm64.tar.gz
3333333333333333333333333333333333333333333333333333333333333333  chezmoi_2.71.0_linux_amd64.tar.gz
4444444444444444444444444444444444444444444444444444444444444444  chezmoi_2.71.0_linux_arm64.tar.gz
5555555555555555555555555555555555555555555555555555555555555555  chezmoi_2.71.0_freebsd_amd64.tar.gz
"""


# ---------------------------------------------------------------------------
# Release.from_payload
# ---------------------------------------------------------------------------
class TestReleaseFromPayload:
    def test_maps_known_fields(self):
        release = update_chezmoi.Release.from_payload(
            {
                "tag_name": "v2.72.0",
                "published_at": "2026-05-01T00:00:00Z",
                "draft": True,
                "prerelease": True,
            }
        )
        assert release == update_chezmoi.Release(
            tag_name="v2.72.0",
            published_at="2026-05-01T00:00:00Z",
            draft=True,
            prerelease=True,
        )

    def test_defaults_missing_fields(self):
        release = update_chezmoi.Release.from_payload({"tag_name": "v2.72.0"})
        assert release.published_at is None
        assert release.draft is False
        assert release.prerelease is False

    def test_defaults_empty_tag_when_absent(self):
        release = update_chezmoi.Release.from_payload({})
        assert release.tag_name == ""


# ---------------------------------------------------------------------------
# fetch_releases_payload
# ---------------------------------------------------------------------------
class TestFetchReleasesPayload:
    def _patch_response(self, monkeypatch, body):
        monkeypatch.setattr(
            update_chezmoi,
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
        releases = update_chezmoi.fetch_releases_payload("owner/repo")
        assert releases == [
            update_chezmoi.Release(
                tag_name="v2.72.0",
                published_at="2026-05-01T00:00:00Z",
                draft=False,
                prerelease=False,
            )
        ]

    def test_raises_on_malformed_json(self, monkeypatch):
        self._patch_response(monkeypatch, b"<html>incident</html>")
        with pytest.raises(update_chezmoi.UpdateError, match="malformed"):
            update_chezmoi.fetch_releases_payload("owner/repo")

    def test_raises_when_payload_is_not_a_list(self, monkeypatch):
        body = json.dumps({"message": "Not Found"}).encode("utf-8")
        self._patch_response(monkeypatch, body)
        with pytest.raises(update_chezmoi.UpdateError, match="array"):
            update_chezmoi.fetch_releases_payload("owner/repo")


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
    return update_chezmoi.Release(
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
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"

    def test_skips_drafts_and_prereleases(self):
        releases = [
            make_release("v2.72.0", days_ago=14, draft=True),
            make_release("v2.72.0-rc.1", days_ago=10, prerelease=True),
            make_release("v2.71.0", days_ago=8),
        ]
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"

    def test_accepts_release_exactly_at_cutoff(self):
        releases = [make_release("v2.71.0", days_ago=7)]
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"

    def test_raises_when_nothing_old_enough(self):
        releases = [
            make_release("v2.72.0", days_ago=1),
            make_release("v2.71.0", days_ago=3),
        ]
        with pytest.raises(update_chezmoi.UpdateError, match="older than"):
            update_chezmoi.select_latest_eligible_release(releases, now=NOW)

    def test_raises_on_empty_release_list(self):
        with pytest.raises(update_chezmoi.UpdateError, match="0 candidates"):
            update_chezmoi.select_latest_eligible_release([], now=NOW)

    def test_skips_release_missing_published_at(self):
        releases = [
            update_chezmoi.Release(
                tag_name="v2.72.0",
                published_at=None,
                draft=False,
                prerelease=False,
            ),
            make_release("v2.71.0", days_ago=8),
        ]
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"

    def test_honors_custom_min_age_days(self):
        releases = [make_release("v2.72.0", days_ago=14)]
        with pytest.raises(update_chezmoi.UpdateError):
            update_chezmoi.select_latest_eligible_release(
                releases, now=NOW, min_age_days=30
            )

    def test_skips_release_with_non_semver_tag(self):
        releases = [
            make_release("nightly", days_ago=14),
            make_release("v2.71.0", days_ago=10),
        ]
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"

    def test_skips_tag_with_path_traversal_chars(self):
        releases = [
            make_release("../../etc/passwd", days_ago=14),
            make_release("v2.71.0", days_ago=10),
        ]
        result = update_chezmoi.select_latest_eligible_release(
            releases, now=NOW
        )
        assert result == "2.71.0"


# ---------------------------------------------------------------------------
# parse_semver_tuple
# ---------------------------------------------------------------------------
class TestParseSemverTuple:
    def test_returns_tuple_for_strict_semver(self):
        assert update_chezmoi.parse_semver_tuple("2.71.0") == (2, 71, 0)

    def test_raises_on_non_numeric_component(self):
        with pytest.raises(update_chezmoi.UpdateError, match="strict semver"):
            update_chezmoi.parse_semver_tuple("2.71.x")

    def test_raises_on_wrong_arity(self):
        with pytest.raises(update_chezmoi.UpdateError, match="strict semver"):
            update_chezmoi.parse_semver_tuple("2.71")

    def test_raises_on_empty_string(self):
        with pytest.raises(update_chezmoi.UpdateError, match="strict semver"):
            update_chezmoi.parse_semver_tuple("")


# ---------------------------------------------------------------------------
# read_pinned_version
# ---------------------------------------------------------------------------
class TestReadPinnedVersion:
    def test_returns_version_from_install_sh(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        assert update_chezmoi.read_pinned_version(install_sh) == "2.70.3"

    def test_raises_when_version_marker_absent(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text("#!/usr/bin/env bash\necho hi\n")
        with pytest.raises(update_chezmoi.UpdateError, match="CHEZMOI_VERSION"):
            update_chezmoi.read_pinned_version(install_sh)


# ---------------------------------------------------------------------------
# extract_platform_checksum
# ---------------------------------------------------------------------------
class TestExtractPlatformChecksum:
    def test_returns_sha_for_known_platform(self):
        sha = update_chezmoi.extract_platform_checksum(
            FIXTURE_CHECKSUMS_TXT, FIXTURE_NEW_VERSION, "darwin_arm64"
        )
        assert sha == "2" * 64

    def test_raises_for_missing_platform(self):
        with pytest.raises(update_chezmoi.UpdateError, match="windows_amd64"):
            update_chezmoi.extract_platform_checksum(
                FIXTURE_CHECKSUMS_TXT, FIXTURE_NEW_VERSION, "windows_amd64"
            )


# ---------------------------------------------------------------------------
# apply_update
# ---------------------------------------------------------------------------
class TestApplyUpdate:
    def test_rewrites_version_and_all_checksums(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        update_chezmoi.apply_update(
            install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
        )
        rewritten = install_sh.read_text()
        assert f'CHEZMOI_VERSION="{FIXTURE_NEW_VERSION}"' in rewritten
        assert f'[darwin_amd64]="{"1" * 64}"' in rewritten
        assert f'[darwin_arm64]="{"2" * 64}"' in rewritten
        assert f'[linux_amd64]="{"3" * 64}"' in rewritten
        assert f'[linux_arm64]="{"4" * 64}"' in rewritten
        # Lines unrelated to checksums must be preserved verbatim.
        assert "declare -rA CHEZMOI_CHECKSUMS=(" in rewritten

    def test_preserves_executable_bit(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        install_sh.chmod(0o755)
        update_chezmoi.apply_update(
            install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
        )
        mode = install_sh.stat().st_mode
        assert mode & stat.S_IXUSR, f"executable bit dropped: {oct(mode)}"

    def test_cleans_up_tmp_file_when_replace_fails(
        self, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        original = install_sh.read_text()

        def boom_replace(_src, _dst):
            raise OSError("simulated rename failure")

        monkeypatch.setattr(update_chezmoi.os, "replace", boom_replace)
        with pytest.raises(OSError, match="simulated rename failure"):
            update_chezmoi.apply_update(
                install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
            )
        # tmp file must not linger after the failure.
        leftovers = list(tmp_path.glob("install.sh*.tmp"))
        assert leftovers == []
        # install.sh on disk must not have been clobbered.
        assert install_sh.read_text() == original

    def test_is_idempotent_when_target_version_already_pinned(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        update_chezmoi.apply_update(
            install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
        )
        snapshot = install_sh.read_text()
        update_chezmoi.apply_update(
            install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
        )
        assert install_sh.read_text() == snapshot

    def test_aborts_when_platform_missing_from_checksums(self, tmp_path):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        partial_text = "\n".join(
            line
            for line in FIXTURE_CHECKSUMS_TXT.splitlines()
            if "linux_arm64" not in line
        ) + "\n"
        with pytest.raises(update_chezmoi.UpdateError, match="linux_arm64"):
            update_chezmoi.apply_update(
                install_sh, FIXTURE_NEW_VERSION, partial_text
            )
        # File on disk was not modified because validation runs first.
        assert install_sh.read_text() == FIXTURE_INSTALL_SH

    def test_aborts_when_version_marker_missing_from_install_sh(
        self, tmp_path
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(
            FIXTURE_INSTALL_SH.replace(
                'readonly CHEZMOI_VERSION="2.70.3"', 'VER="2.70.3"'
            )
        )
        original = install_sh.read_text()
        with pytest.raises(update_chezmoi.UpdateError, match="CHEZMOI_VERSION"):
            update_chezmoi.apply_update(
                install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
            )
        assert install_sh.read_text() == original

    def test_aborts_when_platform_key_missing_from_install_sh(
        self, tmp_path
    ):
        install_sh = tmp_path / "install.sh"
        # Drop the [linux_arm64]=... line from the fixture so the regex
        # cannot find a place to put the new sha256.
        damaged = "\n".join(
            line
            for line in FIXTURE_INSTALL_SH.splitlines()
            if "linux_arm64" not in line
        ) + "\n"
        install_sh.write_text(damaged)
        with pytest.raises(update_chezmoi.UpdateError, match="linux_arm64"):
            update_chezmoi.apply_update(
                install_sh, FIXTURE_NEW_VERSION, FIXTURE_CHECKSUMS_TXT
            )


# ---------------------------------------------------------------------------
# main: end-to-end with monkeypatched network helpers
# ---------------------------------------------------------------------------
def fail_if_called(*_args, **_kwargs):
    """Pytest helper: substitute for a function that must not be invoked."""
    raise AssertionError("function under monkeypatch should not be called")


class TestMain:
    def test_no_op_when_already_pinned_to_latest(self, tmp_path, monkeypatch):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: "2.70.3"
        )
        monkeypatch.setattr(
            update_chezmoi, "fetch_release_checksums", fail_if_called
        )
        rc = update_chezmoi.main([str(install_sh)])
        assert rc == 0
        assert install_sh.read_text() == FIXTURE_INSTALL_SH

    def test_updates_install_sh_when_new_version_available(
        self, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: FIXTURE_NEW_VERSION
        )
        monkeypatch.setattr(
            update_chezmoi,
            "fetch_release_checksums",
            lambda version: FIXTURE_CHECKSUMS_TXT,
        )
        rc = update_chezmoi.main([str(install_sh)])
        assert rc == 0
        rewritten = install_sh.read_text()
        assert f'CHEZMOI_VERSION="{FIXTURE_NEW_VERSION}"' in rewritten
        assert f'[linux_arm64]="{"4" * 64}"' in rewritten

    def test_refuses_downgrade(self, tmp_path, monkeypatch):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        # Pinned is 2.70.3; pretend upstream's latest eligible is older.
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: "2.69.0"
        )
        monkeypatch.setattr(
            update_chezmoi, "fetch_release_checksums", fail_if_called
        )
        with pytest.raises(update_chezmoi.UpdateError, match="downgrade"):
            update_chezmoi.main([str(install_sh)])
        assert install_sh.read_text() == FIXTURE_INSTALL_SH

    def test_writes_github_output_when_changed(
        self, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        github_output = tmp_path / "github_output.txt"
        monkeypatch.setenv("GITHUB_OUTPUT", str(github_output))
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: FIXTURE_NEW_VERSION
        )
        monkeypatch.setattr(
            update_chezmoi,
            "fetch_release_checksums",
            lambda version: FIXTURE_CHECKSUMS_TXT,
        )
        update_chezmoi.main([str(install_sh)])
        contents = github_output.read_text().splitlines()
        assert "changed=true" in contents
        assert f"version={FIXTURE_NEW_VERSION}" in contents

    def test_writes_github_output_when_unchanged(
        self, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        github_output = tmp_path / "github_output.txt"
        monkeypatch.setenv("GITHUB_OUTPUT", str(github_output))
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: "2.70.3"
        )
        monkeypatch.setattr(
            update_chezmoi, "fetch_release_checksums", fail_if_called
        )
        update_chezmoi.main([str(install_sh)])
        contents = github_output.read_text().splitlines()
        assert "changed=false" in contents
        assert "version=2.70.3" in contents

    def test_skips_github_output_when_env_unset(
        self, tmp_path, monkeypatch
    ):
        install_sh = tmp_path / "install.sh"
        install_sh.write_text(FIXTURE_INSTALL_SH)
        monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
        monkeypatch.setattr(
            update_chezmoi, "fetch_latest_version", lambda: "2.70.3"
        )
        monkeypatch.setattr(
            update_chezmoi, "fetch_release_checksums", fail_if_called
        )
        # Must not raise; the helper is a no-op outside GitHub Actions.
        rc = update_chezmoi.main([str(install_sh)])
        assert rc == 0

    def test_returns_nonzero_when_install_sh_missing(self, tmp_path, capsys):
        missing = tmp_path / "does-not-exist.sh"
        rc = update_chezmoi.main([str(missing)])
        assert rc == 1
        captured = capsys.readouterr()
        assert "not found" in captured.err


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
        with update_chezmoi.open_github_url("https://example.invalid/x"):
            pass
        # urllib normalises header names to title case (e.g. User-agent).
        headers = captured["request"].headers
        assert headers.get("User-agent") == update_chezmoi.USER_AGENT

    def test_omits_authorization_when_no_token(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        with update_chezmoi.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert "Authorization" not in headers

    def test_includes_bearer_when_gh_token_set(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.setenv("GH_TOKEN", "secret-test-token")
        monkeypatch.delenv("GITHUB_TOKEN", raising=False)
        with update_chezmoi.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert headers.get("Authorization") == "Bearer secret-test-token"

    def test_falls_back_to_github_token(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.delenv("GH_TOKEN", raising=False)
        monkeypatch.setenv("GITHUB_TOKEN", "fallback-token")
        with update_chezmoi.open_github_url("https://example.invalid/x"):
            pass
        headers = captured["request"].headers
        assert headers.get("Authorization") == "Bearer fallback-token"

    def test_omits_authorization_when_authenticated_false(self, monkeypatch):
        captured = self._capture_request(monkeypatch)
        monkeypatch.setenv("GH_TOKEN", "secret-test-token")
        with update_chezmoi.open_github_url(
            "https://github.com/example/releases/download/v1.0.0/asset",
            authenticated=False,
        ):
            pass
        headers = captured["request"].headers
        # Token must not travel to public download endpoints even when set.
        assert "Authorization" not in headers
        assert headers.get("User-agent") == update_chezmoi.USER_AGENT
