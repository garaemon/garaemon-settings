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
3. Run improve-english skill to fix English quality in the changes
4. Check documentation consistency with the code changes
5. Stage and commit changes
6. Determine push target (fork vs origin)
7. Check diff size and split into multiple PRs if needed
8. Run tests and linters
9. Push and create the PR

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

## Step 3: Run improve-english

Before committing, invoke the `improve-english` skill to fix spelling errors in
identifiers, improve comment English, and translate any Japanese comments. Show the
proposed changes to the user and ask for confirmation before applying. This step
catches English issues early so the PR is clean from the start.

## Step 4: Check Documentation Consistency

Before committing, verify that the code changes do not contradict any documentation
in the repository. Documentation that silently drifts from the code is worse than no
documentation, so treat a found inconsistency as a blocker, not a nice-to-have.

1. Collect the changed files and the diff content (`git diff` / `git diff --cached`
   against the merge base with the default branch).
2. Find documentation that may reference the changed code:
   - `README.md` (root and in changed directories), `CLAUDE.md`, `CONTRIBUTING.md`
   - Everything under `docs/` and any other tracked `*.md` files
   - Grep the docs for identifiers touched by the diff: renamed/removed functions,
     classes, CLI commands and flags, environment variables, config keys, file
     paths, API endpoints, and default values.
3. Compare what the docs claim against what the code now does. Typical
   inconsistencies to catch:
   - Usage examples or sample commands that no longer work
   - Option/flag/env-var names or defaults that changed
   - Described behavior, workflow steps, or directory layouts that changed
   - Docs referencing files that were moved or deleted
4. If inconsistencies are found, show the user a short list of
   `doc file -> what is stale -> proposed fix` and, with their approval, update the
   documentation in the same branch so the docs land in the same PR as the code.
5. If the docs are fine, state that explicitly and move on.

Skip files that are intentionally template-like (e.g. anything under a `templates/`
directory) — placeholders there are expected to look "wrong".

## Step 5: Stage and Commit

Never use `git add .` or `git add -A`. Always specify files explicitly.

Review the changes and group them logically. Write commit messages in English that focus on
the "why" behind the changes, not just what changed.

## Step 6: Determine Push Target

Check the GitHub repository owner to decide where to push:

- Run `gh repo view --json owner -q '.owner.login'` to get the repo owner
- If the owner is `garaemon`, push to `origin`
- Otherwise, check if a fork exists with `gh repo list garaemon --json name,nameWithOwner`
  or `gh repo view garaemon/<repo-name>` and push to the fork

When pushing, always set the upstream tracking branch:

```bash
git push -u <remote> <branch>
```

If a fork doesn't exist yet, create one with `gh repo fork --remote-name fork` and push to it.

## Step 7: Check Diff Size and Split if Needed

This is important: PRs should be small and focused, ideally around 100 lines of diff.

After staging all intended changes, check the total diff size:

```bash
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

## Step 8: Run Tests and Linters

Before creating the PR, always run tests and linters. Find the right commands by checking:

1. `README.md` for test/lint instructions
2. `.github/workflows/` for CI configuration
3. `Makefile`, `package.json`, `Cargo.toml`, `pyproject.toml`, etc.

If tests or linters fail, fix the issues before proceeding. Do not skip this step.

## Step 9: Create the PR

Write the PR body as a cover note for the reviewer. It is not a changelog, a
validation log, or a file-by-file summary. Write it in English, and follow the
`technical-writing` skill.

The body shape and reviewer aids below come from Sentry's `pr-writer` skill:
<https://github.com/getsentry/skills/blob/main/skills/pr-writer/SKILL.md>

### Gather the context

Read the whole branch diff against the base branch, not only the latest commit:

```bash
git log "$BASE"..HEAD --oneline
git diff "$BASE"...HEAD
```

Then answer two questions:

- What behavior changes, and who notices it?
- Why is the change needed now?

If the "why" is not clear from the code, the commits, or the conversation,
ask the user. Never invent a motivation, an issue number, or a benchmark.

### Write the title

- Write one imperative sentence that names the dominant change, such as
  "Fix null handling in format_string and parse_int".
- Avoid vague titles such as "Update", "Cleanup", "Fix bug", or
  "Address feedback".
- Do not end the title with a period.

### Pick the smallest body shape

Choose the shape from the kind of change:

| Change | Body |
| --- | --- |
| Small or obvious | One short paragraph. No headings. |
| Bug fix | The symptom, the root cause, and the fix. |
| Feature or refactor | The changed behavior and its effect, then the non-obvious approach or trade-off. |
| Breaking change | The affected API, config, or CLI surface, and the migration steps. |
| Broad or generated change | Why the breadth is necessary, and where the review should start. |

The default body has two paragraphs:

```markdown
<What changed and what effect it has.>

<Why this approach, the risk, or what the reviewer should focus on.>
```

Make the body easy to scan:

- Put the gist in the first sentence. A reviewer who reads only that sentence
  should know what the PR does.
- Keep each paragraph to three sentences or fewer.
- Use a bulleted list for three or more parallel items.
- Add headings only when the body has two or more distinct topics that a
  reviewer will want to jump between. Then make each heading a descriptive
  phrase, never a generic label such as "Why", "What", "Summary", "Changes", or
  "Test Plan".

### Add reviewer aids only when they save the reviewer work

Each aid must replace reconstruction work that the reviewer would otherwise do:

- A before/after snippet for a changed output, payload, schema, or CLI.
- A small Mermaid diagram for an async flow or a state transition.
- A screenshot for a visual change.
- A review-order note for a broad PR.

Introduce each aid with one sentence that says what to notice in it.

### Leave these out

- A `Test Plan` or validation section for routine checks. Mention testing only
  when it changes the risk, such as a manual check of a case that CI cannot
  cover.
- Pasted command output, CI logs, or commit lists.
- File-by-file narration. The diff already shows the files.
- Empty headings and placeholders.
- The history of the review. Describe the PR as it stands now.

If the repository has a PR template, fill in its headings and keep the text
under each heading as short as the rules above require.

### Create the PR

Write the body to a temporary file, then pass it with `--body-file`:

```bash
gh pr create --title "Fix null handling in format_string and parse_int" \
  --body-file /tmp/pr-body.md
```

A bug fix body looks like this:

```markdown
`format_string` and `parse_int` no longer crash when they receive `None`.
`format_string` now returns `""`, and `parse_int` returns `None`.

Both helpers run on every request, but neither guarded against `None`. Requests
with a missing optional field surfaced as intermittent `AttributeError` and
`TypeError` crashes in the request pipeline.

Generated with [Claude Code](https://claude.com/claude-code)
```

A small change needs only one paragraph:

```markdown
The sidebar section now starts collapsed so it does not take space before the
user needs it. Expanding it keeps the saved preference as before.

Generated with [Claude Code](https://claude.com/claude-code)
```

After creating the PR, display the PR URL to the user.

### Refresh the description after follow-up commits

When later commits change the scope, the approach, or the risk, rewrite the
title and the body around the full diff. Skip the refresh for typo-only or
formatting-only commits.

## Important Rules

- Always use English for commit messages and PR descriptions
- Never use `git add .` -- specify files explicitly
- Always run tests/linters before creating the PR
- Always check markdown documentation for inconsistencies with the code changes,
  and fix stale docs in the same PR
- Always set upstream when pushing (`git push -u`)
- Keep PRs small (~100 lines); split larger changes with user approval
- Write the PR description as a short cover note for the reviewer: gist first,
  the smallest body shape that fits, and the "why"; ask the user if the
  motivation is unclear
- When on the default branch, always create a new branch first
