#!/usr/bin/env python3
"""Resolve the review range and print everything a branch review starts from.

By default the range is the whole branch: from the merge-base with the branch it
merges into, up to HEAD. That base is the pull request's own base branch when one
is open, not the repository default -- for a stacked pull request, diffing
against main would drag in every change from the PRs below and make the reviewer
re-read work that was already reviewed. The resolution order is:

    1. --base, when given explicitly
    2. the base branch of the pull request for the current branch
    3. the repository default branch (no pull request open yet)
    4. a local main/master (no GitHub remote)

The reviewer can also ask for a narrower range -- "just the last commit", "this
one commit", "between these two revisions" -- with --last, --commit or --range.
Those name their endpoints outright and skip the merge-base entirely.

The script also reports the `language` setting from Claude Code's settings
files, so the review is written in the language the user configured rather than
one hard-coded into the skill.

Usage:
    gather_review_context.py                       # whole branch (default)
    gather_review_context.py --last 1              # only the most recent commit
    gather_review_context.py --last 3              # the last three commits
    gather_review_context.py --commit abc123       # that one commit
    gather_review_context.py --range abc123..def456
    gather_review_context.py --base develop        # whole branch, another base
    gather_review_context.py --patch               # any of the above, plus the diff
    gather_review_context.py --patch-for cmd/x.go  # plus one file's diff

Run from anywhere inside the repository checkout.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from pathlib import Path
from typing import Any, cast

from commands import detect_github_host, run_command, run_gh_command

SIZE_THRESHOLD = 200

# git's canonical empty tree, used as the left side when a commit has no parent.
EMPTY_TREE_OBJECT = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

# Claude Code's managed (enterprise) settings file, which outranks every other
# settings file, lives at a different path on each platform.
MANAGED_SETTINGS_PATHS = {
    "darwin": Path("/Library/Application Support/ClaudeCode/managed-settings.json"),
    "win32": Path("C:/Program Files/ClaudeCode/managed-settings.json"),
}
DEFAULT_MANAGED_SETTINGS_PATH = Path("/etc/claude-code/managed-settings.json")


def read_pull_request() -> dict[str, Any] | None:
    """Return the pull request for the current branch, or None if there is none."""
    output = run_gh_command(
        ["gh", "pr", "view", "--json", "number,url,baseRefName,headRefName"],
        check=False,
    )
    if not output.strip():
        return None
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return None


def resolve_existing_revision(candidates: Sequence[str]) -> str | None:
    """Return the first candidate revision that git can resolve, or None."""
    for candidate in candidates:
        verify_command = ["git", "rev-parse", "--verify", "--quiet", candidate]
        if run_command(verify_command, check=False).strip():
            return candidate
    return None


def read_default_branch() -> str | None:
    """Return the repository default branch, or None when it cannot be read."""
    output = run_gh_command(
        ["gh", "repo", "view", "--json", "defaultBranchRef"], check=False
    )
    if output.strip():
        try:
            return json.loads(output)["defaultBranchRef"]["name"]
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    # No GitHub remote to ask, so fall back to whichever conventional branch exists.
    existing = resolve_existing_revision(["refs/heads/main", "refs/heads/master"])
    return existing.removeprefix("refs/heads/") if existing else None


def resolve_review_base(
    explicit_base: str | None, pull_request: dict[str, Any] | None
) -> tuple[str, str]:
    """Return (base_ref, description) for the branch under review."""
    if explicit_base:
        return explicit_base, "explicit --base"
    if pull_request:
        return (
            pull_request["baseRefName"],
            f"base branch of pull request #{pull_request['number']}",
        )
    default_branch = read_default_branch()
    if default_branch:
        return default_branch, "repository default branch (no pull request open)"
    raise RuntimeError("cannot resolve a review base; pass --base explicitly")


def resolve_base_revision(base_ref: str) -> str:
    """Fetch the base and return the revision to diff against.

    Prefers the remote-tracking ref so the review sees the base as it is on the
    server, and falls back to a local branch when there is no remote.
    """
    run_command(["git", "fetch", "origin", base_ref], check=False)
    resolved = resolve_existing_revision([f"origin/{base_ref}", base_ref])
    if resolved is None:
        raise RuntimeError(f"base ref {base_ref!r} does not resolve locally or on origin")
    return resolved


def find_merge_base(base_revision: str, head_revision: str = "HEAD") -> str:
    """Return the common ancestor of two revisions."""
    return run_command(["git", "merge-base", base_revision, head_revision]).strip()


def parse_range_spec(spec: str | None) -> tuple[str, str, bool]:
    """Split a git range into (left, right, uses_merge_base).

    Accepts the two forms git uses plus a bare revision:

        "a..b"  -> ("a", "b", False)   everything b has that a does not
        "a...b" -> ("a", "b", True)    everything b added since they diverged
        "a"     -> ("a", "HEAD", False)

    Raises ValueError when the left endpoint is missing, since a range with no
    starting point has no meaning here.
    """
    spec = (spec or "").strip()
    if not spec:
        raise ValueError("range is empty")
    separator = "..." if "..." in spec else ".." if ".." in spec else None
    if separator is None:
        return spec, "HEAD", False
    left, right = spec.split(separator, 1)
    if not left.strip():
        raise ValueError(f"range {spec!r} has no left endpoint")
    return left.strip(), (right.strip() or "HEAD"), separator == "..."


def build_last_range(count: int) -> tuple[str, str]:
    """Return the (left, right) endpoints covering the last count commits."""
    if count < 1:
        raise ValueError(f"--last needs at least 1 commit, got {count}")
    return f"HEAD~{count}", "HEAD"


def build_commit_range(revision: str) -> tuple[str, str]:
    """Return the (left, right) endpoints covering one commit's own change.

    A root commit has no parent, so its diff is taken against git's empty tree
    rather than against "<revision>^", which would fail to resolve.
    """
    parent = f"{revision}^"
    if resolve_existing_revision([parent]) is None:
        return EMPTY_TREE_OBJECT, revision
    return parent, revision


def format_diff_spec(left: str, right: str) -> str:
    """Render two endpoints as the range string git diff and git log take."""
    return f"{left}..{right}"


def collect_changed_files(
    diff_spec: str,
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Return (reviewable, deleted) lists of (status, path) from the diff."""
    output = run_command(["git", "diff", "--name-status", diff_spec])
    reviewable: list[tuple[str, str]] = []
    deleted: list[tuple[str, str]] = []
    for line in output.splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        status, path = fields[0], fields[-1]
        if status.startswith("D"):
            deleted.append((status, path))
        else:
            reviewable.append((status, path))
    return reviewable, deleted


def measure_size(diff_spec: str) -> tuple[int, int, int]:
    """Return (additions, deletions, file_count) for the diff."""
    output = run_command(["git", "diff", "--numstat", diff_spec])
    additions = deletions = file_count = 0
    for line in output.splitlines():
        if not line.strip():
            continue
        added_text, deleted_text = line.split("\t")[:2]
        file_count += 1
        if added_text != "-":
            additions += int(added_text)
        if deleted_text != "-":
            deletions += int(deleted_text)
    return additions, deletions, file_count


def settings_files() -> list[Path]:
    """Return Claude Code's settings files, highest precedence first.

    Mirrors the order Claude Code itself applies (managed, then the project's
    local file, then the project file, then the user file). Two sources it
    consults are invisible from here and therefore missing: the command-line
    overrides that sit between managed and local, and the `managed-settings.d`
    drop-in directories.
    """
    managed = MANAGED_SETTINGS_PATHS.get(sys.platform, DEFAULT_MANAGED_SETTINGS_PATH)
    repository_root = Path(run_command(["git", "rev-parse", "--show-toplevel"]).strip())
    return [
        managed,
        repository_root / ".claude" / "settings.local.json",
        repository_root / ".claude" / "settings.json",
        Path.home() / ".claude" / "settings.json",
    ]


def resolve_response_language() -> tuple[str | None, Path | None, list[str]]:
    """Return (language, source_path, notes) for the configured `language`.

    language is None when no settings file sets it, in which case the skill
    falls back to the language of the conversation. notes carries the settings
    files that could not be read, so a typo in one is reported instead of
    silently changing which file wins.
    """
    notes: list[str] = []
    for path in settings_files():
        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            continue
        except (OSError, json.JSONDecodeError) as error:
            notes.append(f"could not read {path}: {error}")
            continue
        if not isinstance(parsed, dict):
            continue
        settings = cast("dict[str, Any]", parsed)
        language = settings.get("language")
        if isinstance(language, str) and language.strip():
            return language.strip(), path, notes
    return None, None, notes


def print_section(title: str) -> None:
    """Print a section header."""
    print(f"\n=== {title} ===")


def describe_revision(revision: str) -> str:
    """Render a revision as "<short sha> <subject>" when it names a commit."""
    if revision == EMPTY_TREE_OBJECT:
        return f"{revision}  (git's empty tree: the commit has no parent)"
    described = run_command(
        ["git", "log", "-1", "--format=%h %s", revision], check=False
    ).strip()
    return f"{revision}  ({described})" if described else revision


def report_review_range(
    left: str,
    right: str,
    diff_spec: str,
    description: str,
    pull_request: dict[str, Any] | None,
) -> None:
    """Print the resolved range so the reader can confirm what is under review."""
    print_section("review range")
    print(f"scope:         {description}")
    print(f"diff_spec:     {diff_spec}")
    print(f"from:          {describe_revision(left)}")
    print(f"to:            {describe_revision(right)}")
    branch = run_command(["git", "branch", "--show-current"]).strip()
    print(f"head_ref:      {branch or '(detached HEAD)'}")
    print(f"github_host:   {detect_github_host() or '(no origin remote)'}")
    if pull_request:
        print(f"pull_request:  #{pull_request['number']} {pull_request['url']}")
    else:
        print("pull_request:  (none for this branch)")


def report_response_language() -> None:
    """Print the language the review should be written in."""
    language, source_path, notes = resolve_response_language()
    print_section("review language")
    if language:
        print(f"language:      {language}")
        print(f"source:        {source_path}")
    else:
        print("language:      (unset)")
        print("source:        (no settings file sets `language`)")
    for note in notes:
        print(f"note:          {note}")


def report_size(diff_spec: str, threshold: int) -> None:
    """Print the diff size and flag it when it exceeds the threshold."""
    additions, deletions, file_count = measure_size(diff_spec)
    print_section("size")
    print(f"files changed: {file_count}")
    print(f"additions:     {additions}")
    print(f"deletions:     {deletions}")
    if additions > threshold:
        print(
            f"\nNOTE: additions exceed {threshold}. Flag PR size in Overall Comments "
            "and propose concrete split boundaries, but still review in full."
        )


def report_files(diff_spec: str) -> None:
    """Print the files to review and, separately, the ones to skip."""
    reviewable, deleted = collect_changed_files(diff_spec)
    print_section("files to review (added and modified)")
    for status, path in reviewable:
        print(f"{status}\t{path}")
    print_section("deleted files (do not review)")
    if deleted:
        for status, path in deleted:
            print(f"{status}\t{path}")
    else:
        print("(none)")


def report_stat_and_commits(diff_spec: str) -> None:
    """Print the per-file stat and the commits in the range."""
    print_section("per-file stat")
    print(run_command(["git", "diff", "--stat", diff_spec]).rstrip())
    print_section("commits")
    print(run_command(["git", "log", "--oneline", diff_spec]).rstrip())


def resolve_explicit_range(
    args: argparse.Namespace,
) -> tuple[str, str, str] | None:
    """Return (left, right, description) for --last/--commit/--range, or None.

    These three name their endpoints outright, so no base branch is resolved and
    no merge-base is taken -- the reviewer asked for exactly this span.
    """
    if args.last is not None:
        left, right = build_last_range(args.last)
        commits = "commit" if args.last == 1 else "commits"
        return left, right, f"--last {args.last}: the most recent {args.last} {commits}"
    if args.commit is not None:
        left, right = build_commit_range(args.commit)
        return left, right, f"--commit {args.commit}: that commit's own change"
    if args.range is not None:
        left, right, uses_merge_base = parse_range_spec(args.range)
        if uses_merge_base:
            left = find_merge_base(left, right)
            return left, right, f"--range {args.range}: since the two diverged"
        return left, right, f"--range {args.range}"
    return None


def resolve_branch_range(
    args: argparse.Namespace, pull_request: dict[str, Any] | None
) -> tuple[str, str, str]:
    """Return (left, right, description) for the default whole-branch review."""
    base_ref, base_source = resolve_review_base(args.base, pull_request)
    base_revision = resolve_base_revision(base_ref)
    merge_base = find_merge_base(base_revision)
    return merge_base, "HEAD", f"whole branch against {base_ref} ({base_source})"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--base", help="review the whole branch against this base ref")
    scope.add_argument(
        "--last", type=int, metavar="N",
        help="review only the last N commits (--last 1 is the most recent commit)",
    )
    scope.add_argument("--commit", metavar="REV", help="review only this commit's change")
    scope.add_argument(
        "--range", metavar="SPEC",
        help='review an explicit range: "a..b", "a...b", or "a" (meaning a..HEAD)',
    )
    parser.add_argument(
        "--threshold", type=int, default=SIZE_THRESHOLD,
        help=f"additions above which to flag PR size (default {SIZE_THRESHOLD})",
    )
    parser.add_argument("--patch", action="store_true", help="also print the full diff")
    parser.add_argument("--patch-for", help="also print the diff for one file")
    args = parser.parse_args()

    try:
        pull_request = read_pull_request()
        resolved = resolve_explicit_range(args)
        if resolved is None:
            resolved = resolve_branch_range(args, pull_request)
        left, right, description = resolved
        if resolve_existing_revision([left]) is None:
            raise RuntimeError(f"revision {left!r} does not resolve")
        if resolve_existing_revision([right]) is None:
            raise RuntimeError(f"revision {right!r} does not resolve")
    except (RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    diff_spec = format_diff_spec(left, right)
    report_review_range(left, right, diff_spec, description, pull_request)
    report_response_language()
    report_size(diff_spec, args.threshold)
    report_files(diff_spec)
    report_stat_and_commits(diff_spec)

    if args.patch or args.patch_for:
        command = ["git", "diff", diff_spec]
        if args.patch_for:
            command += ["--", args.patch_for]
        print_section(f"patch{' for ' + args.patch_for if args.patch_for else ''}")
        print(run_command(command).rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
