#!/usr/bin/env python3
"""Upload Markdown reports and their images as one GitHub gist.

The gist goes to the host that the current repository's origin remote points
at. The script prints the gist URL on stdout.

Images that the Markdown files reference by a local path are found and
uploaded automatically. Image links may use any relative path that ends in the
image's file name. They are rewritten to the gist's raw URL.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple, Sequence
from urllib.parse import unquote, urlsplit

IMAGE_EXTENSIONS = ("png", "jpg", "jpeg", "gif", "svg", "webp")
MARKDOWN_EXTENSION = "md"

# Image names go into a regular expression and a URL, so allow only characters
# that are literal in both.
SAFE_FILE_NAME_PATTERN = re.compile(r"^[A-Za-z0-9_-][A-Za-z0-9._-]*$")

# Use gh as the only credential helper so a clone or push on GitHub Enterprise
# authenticates without a terminal prompt.
GH_CREDENTIAL_OPTIONS = (
    "-c",
    "credential.helper=",
    "-c",
    "credential.helper=!gh auth git-credential",
)

# Make SSH fail fast when no key is loaded or port 22 is blocked, so the clone
# falls back to HTTPS. known_hosts often lists github.com but not
# gist.github.com, and batch mode cannot ask to trust a new host key.
SSH_BATCH_OPTIONS = (
    "-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
)

# Captures the target of an inline link, an HTML src attribute, or a reference
# definition, without any title that follows the target.
IMAGE_TARGET_PATTERN = re.compile(
    r"(?:\]\(|src=\"|^\[[^\]]+\]:[ ]+)<?(?P<target>[^)\"\s>]+)",
    re.MULTILINE,
)

SCP_LIKE_URL_PATTERN = re.compile(r"^[^@/\s]+@(?P<host>[^:/\s]+):")


class PostGistError(Exception):
    """A user-facing failure; the message goes to stderr after "error: "."""


def parse_host_from_remote_url(url: str) -> str | None:
    """Return the hostname in a git remote URL, or None for a local path.

    Handles https://, ssh://, and the scp-like shorthand (git@host:owner/repo).
    """
    if "://" in url:
        return urlsplit(url).hostname
    scp_match = SCP_LIKE_URL_PATTERN.match(url)
    return scp_match.group("host") if scp_match else None


def detect_origin_host() -> str:
    """Return the host of the origin remote of the current repository."""
    completed = subprocess.run(
        ["git", "remote", "get-url", "origin"], capture_output=True, text=True
    )
    if completed.returncode != 0:
        raise PostGistError(f"no 'origin' remote in {Path.cwd()}")
    origin_url = completed.stdout.strip()
    host = parse_host_from_remote_url(origin_url)
    if not host:
        raise PostGistError(f"cannot find a host in origin URL: {origin_url}")
    return host


def get_lowercase_extension(path: Path) -> str:
    return path.suffix.lstrip(".").lower()


def is_markdown_file(path: Path) -> bool:
    return get_lowercase_extension(path) == MARKDOWN_EXTENSION


def is_image_file(path: Path) -> bool:
    return get_lowercase_extension(path) in IMAGE_EXTENSIONS


def classify_input_paths(paths: Sequence[Path]) -> tuple[list[Path], list[Path]]:
    """Split paths into (Markdown files, image files), failing on anything else."""
    markdown_paths: list[Path] = []
    image_paths: list[Path] = []
    for path in paths:
        if not path.is_file():
            raise PostGistError(f"file not found: {path}")
        if is_markdown_file(path):
            markdown_paths.append(path)
        elif is_image_file(path):
            image_paths.append(path)
        else:
            raise PostGistError(
                f"only .md files and images ({' '.join(IMAGE_EXTENSIONS)}) "
                f"are supported: {path}"
            )
    return markdown_paths, image_paths


class ReferencedImages(NamedTuple):
    """Local image targets of one Markdown file, as resolved file paths."""

    existing: list[Path]
    missing: list[Path]


def find_referenced_image_paths(markdown_path: Path) -> ReferencedImages:
    """Return the local images that a Markdown file references.

    Relative targets resolve against the Markdown file's directory. Remote
    URLs and non-image targets are skipped, so the gist keeps their original
    link. A local image target that is not a file counts as missing.
    """
    existing: list[Path] = []
    missing: list[Path] = []
    for match in IMAGE_TARGET_PATTERN.finditer(markdown_path.read_text()):
        target = match.group("target")
        if urlsplit(target).scheme:
            continue
        candidate = markdown_path.parent / unquote(target)
        if not is_image_file(candidate):
            continue
        resolved = candidate.resolve()
        destination = existing if candidate.is_file() else missing
        if resolved not in destination:
            destination.append(resolved)
    return ReferencedImages(existing, missing)


def collect_image_paths(
    markdown_paths: Sequence[Path], ignore_missing_images: bool
) -> list[Path]:
    """Return the existing images that the Markdown files reference.

    Fails on a missing image unless ignore_missing_images is set, because the
    gist would otherwise contain a broken link.
    """
    discovered: list[Path] = []
    for markdown_path in markdown_paths:
        references = find_referenced_image_paths(markdown_path)
        if references.missing and not ignore_missing_images:
            raise PostGistError(
                f"referenced image not found in {markdown_path}: "
                + ", ".join(str(path) for path in references.missing)
                + " (pass --ignore-missing-images to skip them)"
            )
        discovered.extend(references.existing)
    return discovered


def merge_image_paths(
    explicit_paths: Sequence[Path], discovered_paths: Sequence[Path]
) -> list[Path]:
    """Return explicit images followed by discovered ones, each file once."""
    merged: list[Path] = []
    seen_resolved: set[Path] = set()
    for path in [*explicit_paths, *discovered_paths]:
        resolved = path.resolve()
        if resolved not in seen_resolved:
            seen_resolved.add(resolved)
            merged.append(path)
    return merged


def assert_unique_base_names(label: str, paths: Sequence[Path]) -> None:
    """Fail when two files would land under the same name in the flat gist."""
    seen_names: set[str] = set()
    for path in paths:
        if path.name in seen_names:
            raise PostGistError(
                f"two {label} files share the name '{path.name}'; a gist is flat"
            )
        seen_names.add(path.name)


def assert_safe_image_names(image_paths: Sequence[Path]) -> None:
    for image_path in image_paths:
        if not SAFE_FILE_NAME_PATTERN.match(image_path.name):
            raise PostGistError(
                f"unsafe image file name '{image_path.name}'; "
                "use letters, digits, '.', '_' and '-'"
            )


def rewrite_image_links(markdown_text: str, image_name: str, raw_url: str) -> str:
    """Point links that end in image_name at raw_url.

    Matches inline links "](path/name.png)" with or without a title, HTML
    attributes src="path/name.png", and reference definitions
    "[id]: path/name.png".
    """
    link_pattern = re.compile(
        r"(\]\(|src=\"|^\[[^\]]+\]:[ ]+)"
        r"([^)\" ]*/)?"
        + re.escape(image_name)
        + r"(\)|\"|[ ]|$)",
        re.MULTILINE,
    )
    return link_pattern.sub(
        lambda match: f"{match.group(1)}{raw_url}{match.group(3)}", markdown_text
    )


def run_git(arguments: Sequence[str], working_directory: Path | None = None) -> None:
    subprocess.run(
        ["git", *arguments], cwd=working_directory, check=True, capture_output=True
    )


def read_git_config(key: str, fallback: str) -> str:
    completed = subprocess.run(
        ["git", "config", key], capture_output=True, text=True
    )
    return completed.stdout.strip() if completed.returncode == 0 else fallback


def convert_to_ssh_url(https_url: str) -> str:
    """Return the scp-like SSH form (git@host:path) of an HTTPS git URL."""
    parts = urlsplit(https_url)
    return f"git@{parts.hostname}:{parts.path.lstrip('/')}"


def clone_gist_repository(git_pull_url: str, clone_directory: Path) -> None:
    """Clone the gist over SSH, or over HTTPS through gh when SSH fails.

    The clone keeps the SSH options in its config, so the later pushes from it
    fail instead of waiting on a password or host key prompt.
    """
    ssh_command = read_git_config("core.sshCommand", "ssh")
    try:
        run_git(
            [
                "clone", "-q",
                "--config", f"core.sshCommand={ssh_command} {SSH_BATCH_OPTIONS}",
                convert_to_ssh_url(git_pull_url), str(clone_directory),
            ]
        )
        return
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors="replace").strip()
        print(f"SSH clone failed, retrying over HTTPS: {detail}", file=sys.stderr)
        shutil.rmtree(clone_directory, ignore_errors=True)
    run_git([*GH_CREDENTIAL_OPTIONS, "clone", "-q", git_pull_url, str(clone_directory)])


def fetch_gist_metadata(gist_id: str) -> dict:
    """Return the gist as the server describes it (git_pull_url, files)."""
    completed = subprocess.run(
        ["gh", "api", f"gists/{gist_id}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise PostGistError(f"cannot read gist {gist_id}: {completed.stderr.strip()}")
    return json.loads(completed.stdout)


def commit_all(message: str, clone_directory: Path) -> None:
    author_name = read_git_config("user.name", "gist-report")
    author_email = read_git_config("user.email", "gist-report@users.noreply.github.com")
    run_git(["add", "-A"], clone_directory)
    # An image that no Markdown link names leaves nothing to commit the second
    # time, and git commit exits non-zero on an empty commit.
    has_staged_changes = subprocess.run(
        ["git", "diff", "--cached", "--quiet"], cwd=clone_directory
    ).returncode != 0
    if not has_staged_changes:
        return
    run_git(
        [
            "-c", f"user.name={author_name}",
            "-c", f"user.email={author_email}",
            "commit", "-q", "-m", message,
        ],
        clone_directory,
    )
    run_git([*GH_CREDENTIAL_OPTIONS, "push", "-q", "origin", "HEAD"], clone_directory)


def push_images_to_gist(
    gist_id: str,
    markdown_names: Sequence[str],
    image_paths: Sequence[Path],
    clone_root: Path,
) -> None:
    """Push the images, then point the Markdown links at the raw URLs.

    gh gist create cannot upload binary files, but the gist is a git
    repository that accepts them. The raw URLs come from the server's own
    answer instead of the URL that gh printed: that URL can lack the user
    name (GitHub Enterprise), and a raw URL built from it would not resolve.
    The images go in a first commit because their raw URLs exist only after
    the push.
    """
    clone_directory = clone_root / "gist"
    try:
        git_pull_url = fetch_gist_metadata(gist_id)["git_pull_url"]
        clone_gist_repository(git_pull_url, clone_directory)
        for image_path in image_paths:
            shutil.copy(image_path, clone_directory / image_path.name)
        commit_all("Add images", clone_directory)

        gist_files = fetch_gist_metadata(gist_id)["files"]
        for markdown_name in markdown_names:
            markdown_path = clone_directory / markdown_name
            rewritten_text = markdown_path.read_text()
            for image_path in image_paths:
                rewritten_text = rewrite_image_links(
                    rewritten_text, image_path.name, gist_files[image_path.name]["raw_url"]
                )
            markdown_path.write_text(rewritten_text)
        commit_all("Link images", clone_directory)
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors="replace").strip()
        raise PostGistError(f"image upload failed: {detail}") from error


def create_gist(
    markdown_paths: Sequence[Path], is_public: bool, description: str | None
) -> str:
    """Create the gist from the Markdown files and return its URL."""
    gh_arguments = ["gh", "gist", "create"]
    if is_public:
        gh_arguments.append("--public")
    if description:
        gh_arguments.extend(["-d", description])
    gh_arguments.extend(str(path) for path in markdown_paths)
    completed = subprocess.run(
        gh_arguments, stdout=subprocess.PIPE, text=True, check=False
    )
    if completed.returncode != 0:
        raise PostGistError("gh gist create failed")
    return completed.stdout.strip().splitlines()[-1]


def parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload Markdown reports and their images as one GitHub gist."
    )
    parser.add_argument("--public", action="store_true", help="create a public gist")
    parser.add_argument("--description", help="gist description")
    parser.add_argument(
        "--ignore-missing-images",
        action="store_true",
        help="skip referenced images that do not exist instead of failing",
    )
    parser.add_argument(
        "paths", nargs="+", type=Path, metavar="FILE", help=".md files, then images"
    )
    return parser.parse_args(argv)


def run(argv: Sequence[str]) -> str:
    """Run the whole upload and return the gist URL."""
    arguments = parse_arguments(argv)
    markdown_paths, explicit_image_paths = classify_input_paths(arguments.paths)
    if not markdown_paths:
        raise PostGistError("no Markdown file given; pass at least one .md file")
    discovered_image_paths = collect_image_paths(
        markdown_paths, arguments.ignore_missing_images
    )
    image_paths = merge_image_paths(explicit_image_paths, discovered_image_paths)
    assert_unique_base_names("Markdown", markdown_paths)
    assert_unique_base_names("image", image_paths)
    assert_safe_image_names(image_paths)

    host = detect_origin_host()
    # An inherited GH_HOST is replaced because the repository decides which
    # server to use.
    os.environ["GH_HOST"] = host

    gist_url = create_gist(markdown_paths, arguments.public, arguments.description)
    if image_paths:
        print(
            f"created {gist_url}; uploading images "
            f"(on failure: GH_HOST={host} gh gist delete {gist_url.rsplit('/', 1)[-1]})",
            file=sys.stderr,
        )
        # A context manager removes the clone even when the push raises.
        with tempfile.TemporaryDirectory() as clone_root:
            push_images_to_gist(
                gist_url.rstrip("/").rsplit("/", 1)[-1],
                [path.name for path in markdown_paths],
                image_paths,
                Path(clone_root),
            )
    return gist_url


def main(argv: Sequence[str]) -> int:
    try:
        print(run(argv))
    except PostGistError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
