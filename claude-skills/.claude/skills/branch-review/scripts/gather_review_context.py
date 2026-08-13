#!/usr/bin/env python3
"""Resolve the review range and print everything a branch review starts from.

The range runs from the merge-base with the branch these changes merge into, up
to HEAD. That base is the pull request's own base branch when one is open, not
the repository default -- for a stacked pull request, diffing against main would
drag in every change from the PRs below and make the reviewer re-read work that
was already reviewed. The resolution order is:

    1. --base, when given explicitly
    2. the base branch of the pull request for the current branch
    3. the repository default branch (no pull request open yet)
    4. a local main/master (no GitHub remote)

Usage:
    gather_review_context.py                       # range, size, files, commits
    gather_review_context.py --base develop        # against another base
    gather_review_context.py --patch               # plus the full unified diff
    gather_review_context.py --patch-for cmd/x.go  # plus one file's diff

Run from anywhere inside the repository checkout.
"""

import argparse
import json
import subprocess
import sys

from commands import run_command

SIZE_THRESHOLD = 200


def read_pull_request():
    """Return the pull request for the current branch, or None if there is none."""
    output = run_command(
        ["gh", "pr", "view", "--json", "number,url,baseRefName,headRefName"],
        check=False,
    )
    if not output.strip():
        return None
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return None


def resolve_existing_revision(candidates):
    """Return the first candidate revision that git can resolve, or None."""
    for candidate in candidates:
        resolved = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", candidate],
            capture_output=True,
        )
        if resolved.returncode == 0:
            return candidate
    return None


def read_default_branch():
    """Return the repository default branch, or None when it cannot be read."""
    output = run_command(["gh", "repo", "view", "--json", "defaultBranchRef"], check=False)
    if output.strip():
        try:
            return json.loads(output)["defaultBranchRef"]["name"]
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    # No GitHub remote to ask, so fall back to whichever conventional branch exists.
    existing = resolve_existing_revision(["refs/heads/main", "refs/heads/master"])
    return existing.removeprefix("refs/heads/") if existing else None


def resolve_review_base(explicit_base, pull_request):
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


def resolve_base_revision(base_ref):
    """Fetch the base and return the revision to diff against.

    Prefers the remote-tracking ref so the review sees the base as it is on the
    server, and falls back to a local branch when there is no remote.
    """
    run_command(["git", "fetch", "origin", base_ref], check=False)
    resolved = resolve_existing_revision([f"origin/{base_ref}", base_ref])
    if resolved is None:
        raise RuntimeError(f"base ref {base_ref!r} does not resolve locally or on origin")
    return resolved


def find_merge_base(base_revision, head_revision="HEAD"):
    """Return the common ancestor of two revisions."""
    return run_command(["git", "merge-base", base_revision, head_revision]).strip()


def format_diff_spec(left, right):
    """Render two endpoints as the range string git diff and git log take."""
    return f"{left}..{right}"


def collect_changed_files(diff_spec):
    """Return (reviewable, deleted) lists of (status, path) from the diff."""
    output = run_command(["git", "diff", "--name-status", diff_spec])
    reviewable, deleted = [], []
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


def measure_size(diff_spec):
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


def print_section(title):
    """Print a section header."""
    print(f"\n=== {title} ===")


def describe_revision(revision):
    """Render a revision as "<short sha> <subject>" when it names a commit."""
    described = run_command(
        ["git", "log", "-1", "--format=%h %s", revision], check=False
    ).strip()
    return f"{revision}  ({described})" if described else revision


def report_review_range(left, right, diff_spec, description, pull_request):
    """Print the resolved range so the reader can confirm what is under review."""
    print_section("review range")
    print(f"scope:         {description}")
    print(f"diff_spec:     {diff_spec}")
    print(f"from:          {describe_revision(left)}")
    print(f"to:            {describe_revision(right)}")
    branch = run_command(["git", "branch", "--show-current"]).strip()
    print(f"head_ref:      {branch or '(detached HEAD)'}")
    if pull_request:
        print(f"pull_request:  #{pull_request['number']} {pull_request['url']}")
    else:
        print("pull_request:  (none for this branch)")


def report_size(diff_spec, threshold):
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


def report_files(diff_spec):
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


def report_stat_and_commits(diff_spec):
    """Print the per-file stat and the commits in the range."""
    print_section("per-file stat")
    print(run_command(["git", "diff", "--stat", diff_spec]).rstrip())
    print_section("commits")
    print(run_command(["git", "log", "--oneline", diff_spec]).rstrip())


def resolve_branch_range(args, pull_request):
    """Return (left, right, description) for the whole-branch review."""
    base_ref, base_source = resolve_review_base(args.base, pull_request)
    base_revision = resolve_base_revision(base_ref)
    merge_base = find_merge_base(base_revision)
    return merge_base, "HEAD", f"whole branch against {base_ref} ({base_source})"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="review the whole branch against this base ref")
    parser.add_argument(
        "--threshold", type=int, default=SIZE_THRESHOLD,
        help=f"additions above which to flag PR size (default {SIZE_THRESHOLD})",
    )
    parser.add_argument("--patch", action="store_true", help="also print the full diff")
    parser.add_argument("--patch-for", help="also print the diff for one file")
    args = parser.parse_args()

    try:
        pull_request = read_pull_request()
        left, right, description = resolve_branch_range(args, pull_request)
        if resolve_existing_revision([left]) is None:
            raise RuntimeError(f"revision {left!r} does not resolve")
        if resolve_existing_revision([right]) is None:
            raise RuntimeError(f"revision {right!r} does not resolve")
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    diff_spec = format_diff_spec(left, right)
    report_review_range(left, right, diff_spec, description, pull_request)
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
