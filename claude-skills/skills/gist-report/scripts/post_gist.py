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
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence
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


def find_referenced_image_paths(markdown_path: Path) -> list[Path]:
    """Return the existing local image files that a Markdown file references.

    Relative targets resolve against the Markdown file's directory. Remote
    URLs, missing files, and non-image targets are skipped, so the gist keeps
    its original link for them.
    """
    found_paths: list[Path] = []
    for match in IMAGE_TARGET_PATTERN.finditer(markdown_path.read_text()):
        target = match.group("target")
        if urlsplit(target).scheme:
            continue
        candidate = markdown_path.parent / unquote(target)
        if is_image_file(candidate) and candidate.is_file():
            resolved = candidate.resolve()
            if resolved not in found_paths:
                found_paths.append(resolved)
    return found_paths


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


def push_images_to_gist(
    gist_url: str,
    markdown_names: Sequence[str],
    image_paths: Sequence[Path],
    clone_root: Path,
) -> None:
    """Clone the gist, add the images, rewrite Markdown links, and push.

    gh gist create cannot upload binary files, but the gist is a git
    repository that accepts them.
    """
    clone_directory = clone_root / "gist"
    try:
        run_git([*GH_CREDENTIAL_OPTIONS, "clone", "-q", f"{gist_url}.git", str(clone_directory)])
        for image_path in image_paths:
            shutil.copy(image_path, clone_directory / image_path.name)
            raw_url = f"{gist_url}/raw/{image_path.name}"
            for markdown_name in markdown_names:
                markdown_path = clone_directory / markdown_name
                markdown_path.write_text(
                    rewrite_image_links(
                        markdown_path.read_text(), image_path.name, raw_url
                    )
                )
        author_name = read_git_config("user.name", "gist-report")
        author_email = read_git_config(
            "user.email", "gist-report@users.noreply.github.com"
        )
        run_git(["add", "-A"], clone_directory)
        run_git(
            [
                "-c", f"user.name={author_name}",
                "-c", f"user.email={author_email}",
                "commit", "-q", "-m", "Add images",
            ],
            clone_directory,
        )
        run_git([*GH_CREDENTIAL_OPTIONS, "push", "-q", "origin", "HEAD"], clone_directory)
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
        "paths", nargs="+", type=Path, metavar="FILE", help=".md files, then images"
    )
    return parser.parse_args(argv)


def run(argv: Sequence[str]) -> str:
    """Run the whole upload and return the gist URL."""
    arguments = parse_arguments(argv)
    markdown_paths, explicit_image_paths = classify_input_paths(arguments.paths)
    if not markdown_paths:
        raise PostGistError("no Markdown file given; pass at least one .md file")
    discovered_image_paths = [
        image_path
        for markdown_path in markdown_paths
        for image_path in find_referenced_image_paths(markdown_path)
    ]
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
                gist_url,
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
