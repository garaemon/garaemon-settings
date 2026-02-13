---
allowed-tools: Bash(gh:*), Bash(git:*), Read(.github/*)
description: "Make a PR"
---

Make a pull request with the following steps:

1. Make a branch. The branch should start with YYYY.MM.DD- prefix.
If you are on a branch, you don't need to make a branch.
2. If there is local change, make a commit.
3. Update origin repository
4. Check the diff between the current branch and the default branch in origin repository.
5. Check the commits with the actual diff and commit message
6. Make a PR by `gh pr create`.
