#!/usr/bin/env python3
"""Refresh the pinned version and sha256 checksums of a tool in install.sh
from its latest GitHub release.

install.sh pins a version and a set of sha256 checksums for each tool it
downloads (currently chezmoi and mise). This script bumps one of them: it
reads the currently pinned version, finds the latest eligible upstream
release, and rewrites the matching ``readonly <TOOL>_VERSION`` line and
``<TOOL>_CHECKSUMS`` array in place.

Select the tool with ``--tool {chezmoi,mise}``. Run from the scheduled
GitHub Actions workflow at .github/workflows/update-pinned-tools.yml (one
matrix job per tool). Exits 0 with no file changes when install.sh already
pins the latest release; otherwise rewrites install.sh in place and exits 0
so the workflow can detect the diff and open a PR.

The per-tool differences (upstream repo, checksum file layout, release
asset naming, platform keys, and the install.sh variable names) are captured
in :class:`ToolSpec`; everything else is tool-agnostic. The transformation
helpers are importable for unit tests.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


# Skip releases newer than this many days. Window meant to let supply-chain
# attacks against an upstream tag (compromised maintainer keys, malicious
# binary swap on the release page) surface publicly before we pin them.
MIN_RELEASE_AGE_DAYS = 7
RELEASES_PAGE_SIZE = 30
USER_AGENT = "garaemon-dotfiles update-pinned-tool"
# Both chezmoi (semver) and mise (CalVer YYYY.M.P) tag as MAJOR.MINOR.PATCH,
# so a single strict triple pattern covers both.
TAG_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
CHECKSUM_LINE_PATTERN = re.compile(r"^([0-9a-f]{64})\s+(\S+)$")


@dataclass(frozen=True)
class ToolSpec:
    """Everything that differs between the tools install.sh pins.

    Frozen so a selected spec cannot be mutated mid-run, keeping a bump
    reproducible.

    Attributes:
        name: Short tool name, used in --tool, log tags, and PR metadata.
        repo: GitHub ``owner/name`` to read releases from.
        version_var: The ``readonly <var>="..."`` line in install.sh.
        checksums_array: The ``declare -rA <array>=(...)`` array in install.sh.
        platforms: Platform keys, matching both the install.sh array keys and
            the ``{platform}`` substituted into ``asset_template``.
        checksums_file: Filename of the release's checksum manifest, formatted
            with ``{version}``. Downloaded from the release's download URL.
        asset_template: Release asset filename whose checksum we want, formatted
            with ``{version}`` and ``{platform}``; matched against the manifest.
    """

    name: str
    repo: str
    version_var: str
    checksums_array: str
    platforms: tuple[str, ...]
    checksums_file: str
    asset_template: str

    def checksums_url(self, version: str) -> str:
        """URL of the checksum manifest for ``version``."""
        filename = self.checksums_file.format(version=version)
        return (
            f"https://github.com/{self.repo}/releases/download/"
            f"v{version}/{filename}"
        )

    def asset_name(self, version: str, platform: str) -> str:
        """Release asset filename whose sha256 we pin for ``platform``."""
        return self.asset_template.format(version=version, platform=platform)

    def version_line_pattern(self) -> re.Pattern:
        """Regex matching the ``readonly <version_var>="..."`` line, capturing
        the current value in group ``value``.
        """
        return re.compile(
            rf'^(readonly {re.escape(self.version_var)}=)"(?P<value>[^"]+)"',
            re.MULTILINE,
        )


# Registry of supported tools. Keys are the --tool values.
TOOLS: dict[str, ToolSpec] = {
    "chezmoi": ToolSpec(
        name="chezmoi",
        repo="twpayne/chezmoi",
        version_var="CHEZMOI_VERSION",
        checksums_array="CHEZMOI_CHECKSUMS",
        platforms=("darwin_amd64", "darwin_arm64", "linux_amd64", "linux_arm64"),
        checksums_file="chezmoi_{version}_checksums.txt",
        asset_template="chezmoi_{version}_{platform}.tar.gz",
    ),
    "mise": ToolSpec(
        name="mise",
        repo="jdx/mise",
        version_var="MISE_VERSION",
        checksums_array="MISE_CHECKSUMS",
        platforms=("linux-x64", "linux-arm64", "macos-x64", "macos-arm64"),
        checksums_file="SHASUMS256.txt",
        asset_template="mise-v{version}-{platform}.tar.gz",
    ),
}


class UpdateError(RuntimeError):
    """Raised when the upstream metadata is missing or malformed."""


@dataclass(frozen=True)
class Release:
    """One GitHub release, narrowed to the fields this script consumes.

    Frozen so a parsed release cannot be mutated between fetch and
    selection, which keeps the eligibility decision reproducible.
    """

    tag_name: str
    published_at: str | None
    draft: bool
    prerelease: bool

    @classmethod
    def from_payload(cls, payload: dict) -> "Release":
        """Build a :class:`Release` from one entry of the GitHub /releases
        JSON array.

        Missing fields fall back to safe defaults (empty tag, no publish
        date, neither draft nor prerelease) so a malformed entry is skipped
        by :func:`select_latest_eligible_release` rather than raising while
        parsing the rest of the page.
        """
        return cls(
            tag_name=payload.get("tag_name", ""),
            published_at=payload.get("published_at"),
            draft=bool(payload.get("draft")),
            prerelease=bool(payload.get("prerelease")),
        )


def open_github_url(
    url: str, *, timeout: int = 30, authenticated: bool = True
):
    """Open a GitHub URL with a User-Agent header (required by api.github.com)
    and, when ``authenticated=True`` and ``GH_TOKEN`` / ``GITHUB_TOKEN`` is
    set, an ``Authorization: Bearer`` header (raises the unauthenticated
    60 req/h IP rate limit on the API).

    Pass ``authenticated=False`` for public release-asset downloads on
    ``github.com``: the asset is public, so the token adds no capability,
    and limiting where the bearer travels narrows credential exposure if
    a future redirect or proxy ever logs request headers.
    """
    headers = {"User-Agent": USER_AGENT}
    if authenticated:
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token:
            headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    return urllib.request.urlopen(request, timeout=timeout)


def fetch_releases_payload(
    repo: str,
    *,
    timeout: int = 30,
    per_page: int = RELEASES_PAGE_SIZE,
) -> list[Release]:
    """Return the most recent releases for ``repo`` as :class:`Release` objects.

    Wraps :class:`urllib.error.URLError` (rate-limit 403, DNS failure, TLS
    issues), :class:`json.JSONDecodeError` (a non-JSON body, e.g. an
    incident-page HTML response), and :class:`UnicodeDecodeError` as
    :class:`UpdateError`, so the ``__main__`` handler emits a single
    tagged error line instead of a stack trace. A JSON body that is not an
    array (e.g. GitHub's ``{"message": ...}`` error object) is also reported
    as :class:`UpdateError` rather than crashing during parsing.
    """
    url = f"https://api.github.com/repos/{repo}/releases?per_page={per_page}"
    try:
        with open_github_url(url, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise UpdateError(f"failed to fetch releases for {repo}: {exc}") from exc
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise UpdateError(
            f"malformed releases response for {repo}: {exc}"
        ) from exc
    if not isinstance(payload, list):
        raise UpdateError(
            f"expected a JSON array of releases for {repo}, "
            f"got {type(payload).__name__}"
        )
    return [Release.from_payload(entry) for entry in payload]


def parse_published_at(value: str) -> datetime.datetime:
    """Parse a GitHub ``published_at`` ISO8601 string to an aware datetime.

    Python 3.11+ accepts the trailing ``Z`` natively; this script pins
    the workflow to 3.12, so no `Z`-to-`+00:00` workaround is needed.
    """
    return datetime.datetime.fromisoformat(value)


def select_latest_eligible_release(
    releases: list[Release],
    *,
    now: datetime.datetime,
    min_age_days: int = MIN_RELEASE_AGE_DAYS,
) -> str:
    """Return the tag (without leading "v") of the first release in
    ``releases`` whose ``published_at`` is at least ``min_age_days`` old.

    GitHub's ``/repos/<repo>/releases`` endpoint returns releases sorted by
    creation date (newest first), so "first eligible" means "newest stable
    release that has been public long enough". Drafts, prereleases, releases
    without ``published_at``, and tags that do not match a strict
    ``MAJOR.MINOR.PATCH`` form are skipped. Raises :class:`UpdateError` if
    nothing in the list qualifies.
    """
    cutoff = now - datetime.timedelta(days=min_age_days)
    for release in releases:
        if release.draft or release.prerelease:
            continue
        if not release.published_at:
            continue
        if parse_published_at(release.published_at) > cutoff:
            continue
        tag = release.tag_name
        if not tag:
            continue
        # removeprefix strips a literal "v" prefix; lstrip("v") would
        # collapse "vvv1.2.3" to "1.2.3", which is not the intent.
        normalised = tag.removeprefix("v")
        if not TAG_PATTERN.fullmatch(normalised):
            continue
        return normalised
    raise UpdateError(
        f"no release older than {min_age_days} days found "
        f"(reviewed {len(releases)} candidates)"
    )


def fetch_latest_version(
    spec: ToolSpec,
    *,
    timeout: int = 30,
    now: datetime.datetime | None = None,
) -> str:
    """Return the latest release tag of ``spec.repo`` that has been public for
    at least :data:`MIN_RELEASE_AGE_DAYS` days, with any leading ``v`` stripped.
    """
    resolved_now = now or datetime.datetime.now(datetime.UTC)
    releases = fetch_releases_payload(spec.repo, timeout=timeout)
    return select_latest_eligible_release(releases, now=resolved_now)


def parse_version_tuple(value: str) -> tuple[int, int, int]:
    """Parse a strict ``MAJOR.MINOR.PATCH`` string into a comparable tuple.

    Works for chezmoi's semver and mise's CalVer alike: in both schemes a
    higher tuple is a newer release, so this drives the downgrade guard.
    """
    parts = value.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise UpdateError(f"not a strict MAJOR.MINOR.PATCH version: {value!r}")
    return (int(parts[0]), int(parts[1]), int(parts[2]))


def read_pinned_version(install_sh_path: Path, spec: ToolSpec) -> str:
    """Read the currently pinned ``<spec.version_var>`` from ``install_sh_path``."""
    text = install_sh_path.read_text()
    match = spec.version_line_pattern().search(text)
    if not match:
        raise UpdateError(
            f"could not find {spec.version_var} in {install_sh_path}"
        )
    return match.group("value")


def fetch_release_checksums(
    version: str,
    spec: ToolSpec,
    *,
    timeout: int = 30,
) -> str:
    """Return the body of ``spec``'s checksum manifest for ``version`` as text.

    Wraps :class:`urllib.error.URLError` and :class:`UnicodeDecodeError`
    as :class:`UpdateError` to keep the failure-mode contract consistent
    with :func:`fetch_releases_payload`.
    """
    url = spec.checksums_url(version)
    try:
        with open_github_url(
            url, timeout=timeout, authenticated=False
        ) as resp:
            return resp.read().decode("utf-8")
    except urllib.error.URLError as exc:
        raise UpdateError(
            f"failed to fetch checksums for v{version}: {exc}"
        ) from exc
    except UnicodeDecodeError as exc:
        raise UpdateError(
            f"malformed checksums file for v{version}: {exc}"
        ) from exc


def extract_platform_checksum(
    checksums_text: str, version: str, platform: str, spec: ToolSpec
) -> str:
    """Pick the sha256 line for ``spec``'s asset for ``platform``.

    Tolerates a leading ``./`` on the filename column (mise's SHASUMS256.txt
    writes ``<sha>  ./mise-...``; chezmoi's checksums.txt has no prefix).
    """
    target = spec.asset_name(version, platform)
    for line in checksums_text.splitlines():
        match = CHECKSUM_LINE_PATTERN.match(line.strip())
        if match and match.group(2).removeprefix("./") == target:
            return match.group(1)
    raise UpdateError(
        f"no checksum found for {platform} in {spec.checksums_file}"
    )


def apply_update(
    install_sh_path: Path,
    new_version: str,
    checksums_text: str,
    spec: ToolSpec,
) -> None:
    """Rewrite ``install_sh_path`` in place with ``new_version`` and the
    matching sha256 entries for ``spec``. Validates all platforms and the
    version line before writing, then performs an atomic rename (preserving
    the original file mode, including the executable bit) so an interrupted
    run cannot leave a half-written file or strip the +x permission.
    """
    resolved = {
        platform: extract_platform_checksum(
            checksums_text, new_version, platform, spec
        )
        for platform in spec.platforms
    }
    text = install_sh_path.read_text()
    rewritten, count = spec.version_line_pattern().subn(
        rf'\1"{new_version}"', text, count=1
    )
    if count != 1:
        raise UpdateError(
            f"could not locate readonly {spec.version_var}=... line in "
            f"{install_sh_path}"
        )
    for platform, sha in resolved.items():
        pattern = re.compile(
            rf'(\[{re.escape(platform)}\]=)"[0-9a-f]{{64}}"'
        )
        rewritten, count = pattern.subn(rf'\1"{sha}"', rewritten, count=1)
        if count != 1:
            raise UpdateError(
                f"could not locate [{platform}]=... entry in "
                f"{install_sh_path}"
            )
    # Append .tmp to the full filename. with_name(...) reads as "same
    # directory, name + .tmp" -- with_suffix(...) would also work but
    # forces the reader to think about suffix replacement semantics.
    tmp_path = install_sh_path.with_name(install_sh_path.name + ".tmp")
    try:
        tmp_path.write_text(rewritten)
        # Path.write_text creates the new file with the umask default
        # (typically 0644), which would silently strip install.sh's
        # executable bit on os.replace. copymode preserves the original.
        shutil.copymode(install_sh_path, tmp_path)
        os.replace(tmp_path, install_sh_path)
    except BaseException:
        # BaseException (not Exception) so SIGINT / SystemExit during the
        # write/replace also unlinks the half-written .tmp before re-raising.
        tmp_path.unlink(missing_ok=True)
        raise


def log(message: str, *, tool: str = "pinned-tool") -> None:
    """Write a tagged informational line to stdout."""
    print(f"[update-{tool}] {message}")


def log_error(message: str, *, tool: str = "pinned-tool") -> None:
    """Write a tagged error line to stderr."""
    print(f"[update-{tool}] ERROR: {message}", file=sys.stderr)


def write_github_output(**outputs: str) -> None:
    """Append ``key=value`` lines to ``$GITHUB_OUTPUT`` when the env var
    points at a writable file. No-op outside GitHub Actions, which keeps
    the script directly runnable from a developer shell.

    Values must be single-line strings; multi-line content would corrupt
    the file because this helper does not emit the ``KEY<<EOF\\n...EOF\\n``
    heredoc form GitHub Actions requires for newline-bearing values.
    """
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            handle.write(f"{key}={value}\n")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments for the script entry point."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--tool",
        choices=sorted(TOOLS),
        default="chezmoi",
        help="Which pinned tool to bump (default: chezmoi)",
    )
    parser.add_argument(
        "install_sh",
        nargs="?",
        default="install.sh",
        type=Path,
        help="Path to install.sh (default: install.sh)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Entry point. Returns 0 on success or no-op, 1 on missing install.sh.
    Raises :class:`UpdateError` on upstream metadata problems (downgrade,
    fetch failure, malformed install.sh); the ``__main__`` handler
    converts that into a non-zero exit.

    Also writes ``changed`` and ``version`` outputs to ``$GITHUB_OUTPUT``
    when invoked from GitHub Actions, so the workflow does not need to
    duplicate the version regex in shell.
    """
    args = parse_args(argv)
    spec = TOOLS[args.tool]
    install_sh_path: Path = args.install_sh
    if not install_sh_path.is_file():
        log_error(f"install.sh not found at {install_sh_path}", tool=spec.name)
        return 1

    pinned = read_pinned_version(install_sh_path, spec)
    latest = fetch_latest_version(spec)

    if parse_version_tuple(latest) < parse_version_tuple(pinned):
        raise UpdateError(
            f"refusing downgrade: pinned v{pinned} > latest eligible v{latest}"
        )

    if pinned == latest:
        log(f"already pinned to v{latest}; nothing to do", tool=spec.name)
        write_github_output(changed="false", version=latest)
        return 0

    log(f"bumping {spec.name} v{pinned} -> v{latest}", tool=spec.name)
    checksums = fetch_release_checksums(latest, spec)
    apply_update(install_sh_path, latest, checksums, spec)
    log(f"updated {install_sh_path}", tool=spec.name)
    write_github_output(changed="true", version=latest)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except UpdateError as exc:
        log_error(str(exc))
        sys.exit(1)
