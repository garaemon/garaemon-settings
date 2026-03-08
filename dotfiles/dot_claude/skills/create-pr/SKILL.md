---
name: create-pr
description: |
  Automate the full PR creation workflow: stage changes, commit, push, and open a GitHub PR.
  Use this skill whenever the user wants to create a pull request, submit code for review,
  push changes upstream, or says things like "PR作って", "PRにして", "make a PR",
  "submit this for review", "push and create PR". Also trigger when the user has finished
  coding and wants to share their work, even if they don't explicitly say "PR".
---

# Create PR Skill

Automate the end-to-end process of creating a GitHub pull request from local changes.

## Workflow Overview

1. Assess the current state (branch, staged/unstaged changes, commits)
2. Create a branch if on the default branch
3. Stage and commit changes
4. Determine push target (fork vs origin)
5. Check diff size and split into multiple PRs if needed
6. Run tests and linters
7. Push and create the PR

## Step 1: Assess Current State

Run these in parallel:
- `git status` (never use `-uall`)
- `git diff` and `git diff --cached`
- `git branch --show-current`
- `git remote -v`
- `git log --oneline -10`

Determine:
- Are there uncommitted changes? Unstaged files?
- Which branch are we on? Is it the default branch (main/master)?
- What remotes exist?

## Step 2: Branch Creation

If on the default branch, create a new branch before making any changes.

Branch naming format: `YYYY.MM.DD-<descriptive-topic>`
- Use today's date
- Use lowercase kebab-case for the topic
- Example: `2026.03.07-fix-auth-token-refresh`

Ask the user what the topic should be if it's not obvious from context.

## Step 3: Stage and Commit

Never use `git add .` or `git add -A`. Always specify files explicitly.

Review the changes and group them logically. Write commit messages in English that focus on
the "why" behind the changes, not just what changed.

## Step 4: Determine Push Target

Check the GitHub repository owner to decide where to push:
- Run `gh repo view --json owner -q '.owner.login'` to get the repo owner
- If the owner is `garaemon`, push to `origin`
- Otherwise, check if a fork exists with `gh repo list garaemon --json name,nameWithOwner`
  or `gh repo view garaemon/<repo-name>` and push to the fork

When pushing, always set the upstream tracking branch:
```
git push -u <remote> <branch>
```

If a fork doesn't exist yet, create one with `gh repo fork --remote-name fork` and push to it.

## Step 5: Check Diff Size and Split if Needed

This is important: PRs should be small and focused, ideally around 100 lines of diff.

After staging all intended changes, check the total diff size:
```
git diff --cached --stat
git diff --cached | wc -l
```

If the diff exceeds ~100 lines, split it into multiple PRs by functionality:
1. Analyze the changes and group them by feature/concern
2. Present the proposed split to the user for approval
3. For each group:
   - Create a separate branch from the base
   - Cherry-pick or stage only the relevant files
   - Create a separate PR
4. If changes have dependencies, note this in each PR description

Ask the user before splitting. They may prefer a single larger PR in some cases.

## Step 6: Run Tests and Linters

Before creating the PR, always run tests and linters. Find the right commands by checking:
1. `README.md` for test/lint instructions
2. `.github/workflows/` for CI configuration
3. `Makefile`, `package.json`, `Cargo.toml`, `pyproject.toml`, etc.

If tests or linters fail, fix the issues before proceeding. Do not skip this step.

## Step 7: Create the PR

Write the PR description in English. Focus on the "why" — background, motivation, and the
problem being solved. If the "why" isn't clear from the code or commits, ask the user.

Do NOT use generic section headers like "## Why", "## What", "## Summary". Instead, use
descriptive headers that convey the actual content. The reader should understand the gist
just from scanning the headers.

**Example:**
```
gh pr create --title "Fix null handling in utility functions" --body "$(cat <<'EOF'
## Prevent crashes when None is passed to format_string and parse_int

These functions are called throughout the codebase but never guarded against
None input. In production, this surfaces as intermittent AttributeError and
TypeError crashes in the request pipeline.

## Add None guard and extend exception handling

- `format_string`: return empty string for None input
- `parse_int`: catch TypeError in addition to ValueError

## Verified with unit tests

- `format_string(None)` returns `""`
- `parse_int(None)` returns `None`

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

After creating the PR, display the PR URL to the user.

## Important Rules

- Always use English for commit messages and PR descriptions
- Never use `git add .` -- specify files explicitly
- Always run tests/linters before creating the PR
- Always set upstream when pushing (`git push -u`)
- Keep PRs small (~100 lines); split larger changes with user approval
- Focus PR descriptions on the "why", ask the user if the motivation is unclear
- When on the default branch, always create a new branch first
