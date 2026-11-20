---
name: fix-merge-conflict
description: >
  Resolve merge conflicts between the current branch (a pull request branch)
  and its base branch: merge the latest base into the branch, resolve every
  conflicted hunk while keeping the intent of both sides, run the tests and
  linters, and commit the merge. Use this skill when the user says things like
  "コンフリクト直して", "マージコンフリクト解消して", "PRのコンフリクト直して",
  "fix merge conflicts", "resolve conflicts", or when a PR cannot be merged
  because it conflicts with its base branch.
---

# Fix Merge Conflict

This skill merges the base branch into the current branch and resolves the
conflicts.

## Workflow

1. **Find the base branch.** Use the base of the open PR when one exists
   (`gh pr view --json baseRefName -q .baseRefName`). Otherwise use the
   repository default branch.
2. **Check the working tree.** Stop and ask the user if there are
   uncommitted changes.
3. **Merge the base.** Run `git fetch origin <base>` and then
   `git merge origin/<base>`. Merge instead of rebasing so that the branch
   history stays intact and no force push is needed.
4. **Resolve each conflicted file.** List the files with
   `git diff --name-only --diff-filter=U`. For each file:
   - Read both sides of every hunk and the commits that introduced them
     (`git log --oneline -n 5 origin/<base> -- <file>`).
   - Keep the intent of both sides. Do not drop a change just to make the
     conflict go away.
   - For generated files such as lockfiles, regenerate them with the
     project's tool instead of editing the markers by hand.
   - Ask the user when the two sides contradict each other and the right
     answer is unclear.
5. **Verify.** Confirm that no conflict markers remain
   (`git grep -nE '^(<<<<<<<|=======|>>>>>>>)'`). Then run the project's
   build, tests, and linters.
6. **Commit.** Stage the resolved files explicitly by name and run
   `git commit --no-edit` to keep the default merge message.
7. **Report.** Summarize how each file was resolved. Push only when the user
   asks.
