"""Verify that the sha256 checksums embedded in install.sh match the
official chezmoi release checksums.txt for the pinned version.

This is a network-dependent regression test: it catches typos in the
embedded checksum table, accidental drift after a version bump, and
platform keys that don't correspond to a real release artifact.
"""

import re
import urllib.request
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parent.parent
INSTALL_SH = REPO_ROOT / "install.sh"
CHECKSUMS_URL_TEMPLATE = (
    "https://github.com/twpayne/chezmoi/releases/download/"
    "v{version}/chezmoi_{version}_checksums.txt"
)
MISE_CHECKSUMS_URL_TEMPLATE = (
    "https://github.com/jdx/mise/releases/download/v{version}/SHASUMS256.txt"
)


def read_install_sh():
    return INSTALL_SH.read_text()


def extract_pinned_version(text):
    match = re.search(
        r'^readonly CHEZMOI_VERSION="([^"]+)"', text, re.MULTILINE
    )
    assert match, "CHEZMOI_VERSION not found in install.sh"
    return match.group(1)


def extract_pinned_checksums(text):
    """Return dict of platform -> sha256 from the CHEZMOI_CHECKSUMS array."""
    match = re.search(
        r"declare -rA CHEZMOI_CHECKSUMS=\((.+?)\)", text, re.DOTALL
    )
    assert match, "CHEZMOI_CHECKSUMS array not found in install.sh"
    body = match.group(1)
    entry_pattern = re.compile(r'\[(\w+)\]="([0-9a-f]{64})"')
    found = dict(entry_pattern.findall(body))
    assert found, "no CHEZMOI_CHECKSUMS entries parsed from install.sh"
    return found


def fetch_official_checksums(version):
    url = CHECKSUMS_URL_TEMPLATE.format(version=version)
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return resp.read().decode("utf-8")
    except Exception as exc:
        pytest.skip(f"could not fetch official checksums.txt: {exc}")


def parse_official_checksums(text, version):
    """Parse `<sha256>  chezmoi_<version>_<os>_<arch>.tar.gz` lines into a
    {platform: sha256} dict.
    """
    line_pattern = re.compile(
        rf"^([0-9a-f]{{64}})\s+chezmoi_{re.escape(version)}_(\w+_\w+)\.tar\.gz$"
    )
    out = {}
    for line in text.splitlines():
        m = line_pattern.match(line.strip())
        if m:
            out[m.group(2)] = m.group(1)
    return out


def extract_mise_pinned_version(text):
    match = re.search(
        r'^readonly MISE_VERSION="([^"]+)"', text, re.MULTILINE
    )
    assert match, "MISE_VERSION not found in install.sh"
    return match.group(1)


def extract_mise_pinned_checksums(text):
    """Return dict of platform -> sha256 from the MISE_CHECKSUMS array."""
    match = re.search(
        r"declare -rA MISE_CHECKSUMS=\((.+?)\)", text, re.DOTALL
    )
    assert match, "MISE_CHECKSUMS array not found in install.sh"
    body = match.group(1)
    # mise platform keys contain a hyphen (e.g. linux-x64), so \w+ won't do.
    entry_pattern = re.compile(r'\[([\w-]+)\]="([0-9a-f]{64})"')
    found = dict(entry_pattern.findall(body))
    assert found, "no MISE_CHECKSUMS entries parsed from install.sh"
    return found


def fetch_official_mise_checksums(version):
    url = MISE_CHECKSUMS_URL_TEMPLATE.format(version=version)
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            return resp.read().decode("utf-8")
    except Exception as exc:
        pytest.skip(f"could not fetch official mise SHASUMS256.txt: {exc}")


def parse_official_mise_checksums(text, version):
    """Parse `<sha256>  ./mise-v<version>-<platform>.tar.gz` lines into a
    {platform: sha256} dict.
    """
    line_pattern = re.compile(
        rf"^([0-9a-f]{{64}})\s+\.?/?mise-v{re.escape(version)}-"
        rf"([\w-]+)\.tar\.gz$"
    )
    out = {}
    for line in text.splitlines():
        m = line_pattern.match(line.strip())
        if m:
            out[m.group(2)] = m.group(1)
    return out


class TestPinnedChecksums:
    def test_each_pinned_entry_matches_official_release(self):
        text = read_install_sh()
        version = extract_pinned_version(text)
        embedded = extract_pinned_checksums(text)

        official_text = fetch_official_checksums(version)
        official = parse_official_checksums(official_text, version)

        assert official, (
            f"no tarball entries parsed from official checksums.txt for "
            f"v{version}; the release format may have changed"
        )

        for platform, embedded_sha in sorted(embedded.items()):
            assert platform in official, (
                f"platform {platform!r} not present in official checksums "
                f"for v{version}; possible typo in install.sh"
            )
            assert official[platform] == embedded_sha, (
                f"sha256 mismatch for {platform} (v{version}): "
                f"install.sh has {embedded_sha}, "
                f"official has {official[platform]}"
            )


class TestMisePinnedChecksums:
    def test_each_pinned_entry_matches_official_release(self):
        text = read_install_sh()
        version = extract_mise_pinned_version(text)
        embedded = extract_mise_pinned_checksums(text)

        official_text = fetch_official_mise_checksums(version)
        official = parse_official_mise_checksums(official_text, version)

        assert official, (
            f"no tarball entries parsed from official mise SHASUMS256.txt for "
            f"v{version}; the release format may have changed"
        )

        for platform, embedded_sha in sorted(embedded.items()):
            assert platform in official, (
                f"mise platform {platform!r} not present in official "
                f"checksums for v{version}; possible typo in install.sh"
            )
            assert official[platform] == embedded_sha, (
                f"sha256 mismatch for mise {platform} (v{version}): "
                f"install.sh has {embedded_sha}, "
                f"official has {official[platform]}"
            )
