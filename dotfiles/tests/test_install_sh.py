"""Tests for install.sh.

The script is bash 4+ (uses associative arrays). We test it by:
- sourcing it under bash 4+ to call individual functions in isolation, and
- running it end-to-end against a temporary $HOME for the install_chezmoi
  integration test (downloads the pinned chezmoi release over the network).

Tests that need bash 4+ are skipped automatically when no such interpreter
is available on the test host (e.g. macOS with only the system bash 3.2).
"""

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
INSTALL_SH = REPO_ROOT / "install.sh"


def read_pinned_version():
    """Return the chezmoi version pinned in install.sh.

    Read dynamically so the integration test follows install.sh after a
    version bump instead of drifting against a hardcoded constant.
    """
    text = INSTALL_SH.read_text()
    match = re.search(
        r'^readonly CHEZMOI_VERSION="([^"]+)"', text, re.MULTILINE
    )
    assert match, "CHEZMOI_VERSION not found in install.sh"
    return match.group(1)


PINNED_VERSION = read_pinned_version()


def find_bash_at_least(major):
    """Return the path to a bash whose major version is >= major, or None."""
    seen = set()
    candidates = [
        shutil.which("bash"),
        "/opt/homebrew/bin/bash",
        "/usr/local/bin/bash",
        "/bin/bash",
    ]
    for path in candidates:
        if not path or path in seen:
            continue
        seen.add(path)
        if not Path(path).exists():
            continue
        result = subprocess.run(
            [path, "-c", "echo ${BASH_VERSINFO[0]:-0}"],
            capture_output=True,
            text=True,
        )
        if (
            result.returncode == 0
            and result.stdout.strip().isdigit()
            and int(result.stdout.strip()) >= major
        ):
            return path
    return None


def find_bash_below(major):
    """Return the path to a bash whose major version is < major, or None."""
    seen = set()
    candidates = [
        "/bin/bash",
        shutil.which("bash"),
        "/usr/local/bin/bash",
        "/opt/homebrew/bin/bash",
    ]
    for path in candidates:
        if not path or path in seen:
            continue
        seen.add(path)
        if not Path(path).exists():
            continue
        result = subprocess.run(
            [path, "-c", "echo ${BASH_VERSINFO[0]:-0}"],
            capture_output=True,
            text=True,
        )
        if (
            result.returncode == 0
            and result.stdout.strip().isdigit()
            and int(result.stdout.strip()) < major
        ):
            return path
    return None


BASH4 = find_bash_at_least(4)
BASH3 = find_bash_below(4)
requires_bash4 = pytest.mark.skipif(
    BASH4 is None, reason="bash 4+ required for associative arrays"
)


def source_and_run(snippet, env=None):
    """Source install.sh under bash 4+ and execute the given snippet.

    Returns the CompletedProcess. The main() entry point is guarded by a
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] check, so sourcing only loads the
    helpers and constants -- main is not invoked.
    """
    test_env = os.environ.copy()
    if env:
        test_env.update(env)
    full = f'source "{INSTALL_SH}"\n{snippet}'
    return subprocess.run(
        [BASH4, "-c", full],
        env=test_env,
        capture_output=True,
        text=True,
    )


# ---------------------------------------------------------------------------
# bash version guard
# ---------------------------------------------------------------------------
class TestBashVersionGuard:
    def test_aborts_when_bash_below_4(self):
        if BASH3 is None:
            pytest.skip("no bash < 4 available to exercise the guard")
        result = subprocess.run(
            [BASH3, str(INSTALL_SH)], capture_output=True, text=True
        )
        assert result.returncode != 0
        assert "bash 4 or later required" in result.stderr


# ---------------------------------------------------------------------------
# detect_platform
# ---------------------------------------------------------------------------
@requires_bash4
class TestDetectPlatform:
    def test_returns_supported_os_arch(self):
        result = source_and_run("detect_platform")
        assert result.returncode == 0, result.stderr
        platform = result.stdout.strip()
        assert "_" in platform
        os_part, arch_part = platform.split("_", 1)
        assert os_part in {"linux", "darwin"}
        assert arch_part in {"amd64", "arm64"}


# ---------------------------------------------------------------------------
# compute_sha256
# ---------------------------------------------------------------------------
@requires_bash4
class TestComputeSha256:
    def test_matches_known_sha256(self, tmp_path):
        f = tmp_path / "hello.txt"
        f.write_bytes(b"hello\n")
        # printf 'hello\n' | sha256sum
        expected = (
            "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"  # pragma: allowlist secret
        )
        result = source_and_run(f'compute_sha256 "{f}"')
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == expected


# ---------------------------------------------------------------------------
# lookup_checksum
# ---------------------------------------------------------------------------
@requires_bash4
class TestLookupChecksum:
    def test_returns_pinned_checksum_for_known_platform(self):
        result = source_and_run("lookup_checksum darwin_arm64")
        assert result.returncode == 0, result.stderr
        sha = result.stdout.strip()
        assert len(sha) == 64
        assert all(c in "0123456789abcdef" for c in sha)

    def test_fails_for_unknown_platform(self):
        result = source_and_run("lookup_checksum freebsd_amd64")
        assert result.returncode != 0
        assert "no pinned checksum" in result.stderr


# ---------------------------------------------------------------------------
# install_chezmoi end-to-end
# ---------------------------------------------------------------------------
@requires_bash4
class TestInstallChezmoiIntegration:
    """Network-dependent: downloads the pinned chezmoi release from GitHub,
    verifies the embedded sha256, and installs it under a temporary $HOME.
    """

    def test_installs_pinned_version_into_isolated_home(self, tmp_path):
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        env = {
            "HOME": str(fake_home),
            # Drop the test host's ${HOME}/.local/bin from PATH so the
            # script's resolve_chezmoi cannot find an already-installed
            # chezmoi and short-circuit the download.
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        }
        result = source_and_run("install_chezmoi", env=env)
        assert result.returncode == 0, (
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        installed = fake_home / ".local" / "bin" / "chezmoi"
        assert installed.is_file()
        assert os.access(installed, os.X_OK)
        version = subprocess.run(
            [str(installed), "--version"], capture_output=True, text=True
        )
        assert version.returncode == 0, version.stderr
        assert f"v{PINNED_VERSION}" in version.stdout

    def test_aborts_on_checksum_mismatch(self, tmp_path):
        """Tamper with the pinned checksum at runtime; the script must
        refuse to install the (genuine) tarball.
        """
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        env = {
            "HOME": str(fake_home),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        }
        # We cannot reassign a readonly array, so we override the
        # lookup_checksum function instead to return a deliberately wrong
        # sha. install_chezmoi should detect the mismatch and exit non-zero.
        snippet = (
            "lookup_checksum() { "
            "printf '%s\\n' '0000000000000000000000000000000000000000000000000000000000000000'; "
            "}\n"
            "install_chezmoi"
        )
        result = source_and_run(snippet, env=env)
        assert result.returncode != 0
        assert "sha256 mismatch" in result.stderr
        assert not (fake_home / ".local" / "bin" / "chezmoi").exists()


# ---------------------------------------------------------------------------
# Full end-to-end run of install.sh as a script
# ---------------------------------------------------------------------------
@requires_bash4
class TestInstallShEndToEnd:
    """Execute install.sh directly (not sourced) with $HOME pointed at a
    temporary directory. Exercises the full bootstrap path: bash version
    check, chezmoi install with sha256 verification, and chezmoi apply of
    this repository's dotfiles.
    """

    def test_full_run_installs_chezmoi_and_applies_dotfiles(self, tmp_path):
        fake_home = tmp_path / "home"
        fake_home.mkdir()
        env = os.environ.copy()
        env.update(
            {
                "HOME": str(fake_home),
                # Drop the test host's PATH augmentations so resolve_chezmoi
                # cannot pick up an already-installed chezmoi.
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            }
        )
        result = subprocess.run(
            [BASH4, str(INSTALL_SH)],
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        # The verified chezmoi binary landed in the isolated $HOME.
        installed_chezmoi = fake_home / ".local" / "bin" / "chezmoi"
        assert installed_chezmoi.is_file()
        # apply_dotfiles materialised at least one dotfile under the
        # isolated $HOME -- pick zshrc as a stable target managed by this
        # repo's dot_zshrc source entry.
        assert (fake_home / ".zshrc").is_file()
        # The final log line is emitted only after apply_dotfiles succeeds.
        assert "Done." in result.stdout
