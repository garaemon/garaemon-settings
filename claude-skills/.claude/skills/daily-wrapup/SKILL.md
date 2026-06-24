---
name: daily-wrapup
description: |
  Wrap up the user's day: write a Japanese end-of-day summary of their
  GitHub activity for a given day (default: today) into their org-roam daily
  note, then commit and push the org repository (asking the user to confirm
  before the commit). This is the evening counterpart to the morning-brief
  skill — morning-brief plans the day ahead, daily-wrapup records what
  actually got done. The summary covers pull requests and issues the user
  touched that day and the commits they authored, grouped by repository and
  synthesized into a short narrative. Activity is read with `gh search`; the
  note is written to `$ORG_DIR/org-roam/daily/YYYY-MM-DD.org` and tagged as
  Claude-generated and unreviewed.
  Trigger when the user asks to wrap up or record what they did today, or
  for a daily log/standup at end of day, with phrases like "今日のまとめ",
  "今日のラップアップ", "一日のまとめ", "今日やったことまとめて", "日報",
  "日次まとめ", "今日の締め", "daily wrapup", "wrap up my day",
  "today's summary", "今日の活動まとめて".
allowed-tools: Bash(gh search:*), Bash(gh api:*), Bash(jq:*), Bash(date:*), Bash(uuidgen:*), Bash(mkdir:*), Bash(git:*)
---

# Daily Wrapup Skill

Wrap up the user's day by summarizing their GitHub activity and appending it
to their org-roam daily note as a Claude-generated, unreviewed subtree, then
commit and push the org repository — but only after the user confirms the
commit. This is the end-of-day counterpart to the `morning-brief` skill.

The daily note lives in a private repository (the user's org), so the note
itself is written in Japanese and may contain real names and titles. This
SKILL.md stays generic and English, and never hardcodes a username or path
(the GitHub login is detected with `gh api user`; the org path comes from
`$ORG_DIR`).

## Prerequisites

- `gh` (GitHub CLI) is authenticated (`gh auth status` succeeds). The search
  covers private repositories the authenticated user can see.
- `ORG_DIR` points at the user's org repository (the one that contains
  `org-roam/daily/`). If it is unset, default to `$HOME/org` and, if that is
  not a git work tree, stop and ask the user to export `ORG_DIR`.
- `git`, `jq`, `date`, and `uuidgen` are available on the host.

## Workflow

### Step 1: Resolve the day, paths, and identity

```bash
DAY="${1:-$(date +%Y-%m-%d)}"          # allow an explicit YYYY-MM-DD argument
USER_LOGIN="$(gh api user --jq .login)"
ORG_DIR="${ORG_DIR:-$HOME/org}"
DAILY_DIR="$ORG_DIR/org-roam/daily"
DAILY_FILE="$DAILY_DIR/$DAY.org"
mkdir -p "$DAILY_DIR"
```

Confirm `ORG_DIR` is a git work tree (`git -C "$ORG_DIR" rev-parse` succeeds);
if not, stop and ask the user to set `ORG_DIR`.

### Step 2: Gather the day's GitHub activity

Use `gh search`, which returns reliable titles and states (the
`users/<login>/events` API ships stripped payloads — no PR titles or commit
messages — so do not use it here).

```bash
# Pull requests the user touched that day (opened, merged, commented).
gh search prs --author="$USER_LOGIN" --updated="$DAY" \
  --json number,title,repository,state,url --limit 50

# Issues the user touched that day. gh search issues also returns PRs, so
# drop entries where isPullRequest is true.
gh search issues --author="$USER_LOGIN" --updated="$DAY" \
  --json number,title,repository,state,url,isPullRequest --limit 50

# Commits the user authored that day (repository.fullName + message).
gh search commits --author="$USER_LOGIN" --committer-date="$DAY" \
  --json repository,sha,commit --limit 100
```

Notes:

- A day with no activity is not an error. If all three are empty, tell the
  user there is nothing to record for that day and stop (do not write or
  commit an empty note).
- Commit search returns merge commits (`Merge pull request #N …`) alongside
  real commits; the PR list already captures the PR-level view, so prefer
  the PR titles for the narrative and use commit subjects as supporting
  detail. Do not list a long wall of merge commits.

### Step 3: Synthesize a short Japanese summary

Group the activity by repository. For each repository, lead with the PRs
(title + state: merged / open / closed) and the issues, then fold in the
notable commit subjects. Write a brief synthesis, not a raw dump — a few
bullet lines per repository describing what actually changed. Keep it
scannable.

### Step 4: Write the daily org note

The note is an org-roam daily file. Two cases:

- **File does not exist**: create it with the org-roam node header, then the
  Claude subtree:

  ```org
  :PROPERTIES:
  :ID:       <uuidgen output, uppercase>
  :END:
  #+title: <DAY>
  * <DAY Dow HH:MM> GitHub activity                                :claude:
  :PROPERTIES:
  :STATUS:   unreviewed
  :GENERATED_BY: claude-code/daily-wrapup
  :END:

  ** <owner/repo>
  - …
  ```

- **File already exists**: do not touch the existing header or entries.
  Append the same `* … :claude:` subtree to the end of the file.

Provenance rules (from the project plan):

- Tag the generated subtree headline `:claude:`. When this skill runs
  unattended (a `claude -p` batch run with no human in the loop), also add
  `:autogenerated:` (org tags cannot contain hyphens, so use
  `autogenerated`, not `auto-generated`).
- Put `:STATUS: unreviewed` in the subtree's property drawer. Review happens
  by editing this tag in org, not through a git PR.
- Generate a fresh `:ID:` with `uuidgen` only when creating a new file;
  never invent or reuse an id for an existing node.

Write the file with the editor tools (not a shell heredoc) so the Japanese
body is handled cleanly.

### Step 5: Confirm, then commit and push the org repo

Stage only the daily file — never `git add .`:

```bash
git -C "$ORG_DIR" add "org-roam/daily/$DAY.org"
git -C "$ORG_DIR" --no-pager diff --cached -- "org-roam/daily/$DAY.org"
BRANCH="$(git -C "$ORG_DIR" branch --show-current)"
```

Then show the user a short confirmation in Japanese: the day, the target
branch (`$BRANCH`), and a one-line summary of what was written, and ask
plainly whether to commit and push (e.g. `org に commit & push していい？`).
Wait for an explicit yes. The org repo may be on a non-default branch — name
the branch in the prompt so the user can catch it; if they want it on
`main`, they switch the org repo themselves first.

On confirmation, commit in English and push the current branch:

```bash
git -C "$ORG_DIR" commit -m "Add daily wrapup for $DAY"
git -C "$ORG_DIR" push || git -C "$ORG_DIR" push -u origin HEAD
```

If the user declines, leave the file written but uncommitted and stop. Do
not commit without an explicit yes.

## Output rules

- The org note body is Japanese and may include real repository names, PR
  titles, and commit subjects — it lives in the private org repo.
- This SKILL.md and the commit message stay English. Never hardcode the
  username or org path; resolve them at run time.
- Synthesize; do not dump every commit. A reader should understand the day
  from a few lines per repository.
- Record only real activity returned by `gh search`. Do not invent work.

## Error handling

- `gh` not authenticated: stop and tell the user to run `gh auth login`.
- `ORG_DIR` not a git work tree: stop and ask the user to export `ORG_DIR`.
- No activity for the day: say so and stop without writing or committing.
- `git push` fails (no upstream, rejected): report the error and leave the
  commit in place; do not force-push.

## Out of scope

- Sources other than GitHub. Shell history (atuin) and Claude Code session
  logs are planned future sources for this skill but are not read yet.
- A PR flow for the org repo. The daily note is committed directly to the
  org repo's current branch (with confirmation), not via a pull request.
- Calendar and mail. Those belong to the `morning-brief` skill.

## Security note

Activity is read with the authenticated `gh` CLI on the host and covers the
user's own public and private GitHub activity. The skill writes only to the
user's org repository and commits only the single daily file it generated,
after an explicit confirmation.
