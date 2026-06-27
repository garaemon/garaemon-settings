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
  synthesized into a short narrative, alongside the day's events from the
  user's own (primary) Google Calendar. GitHub is read with `gh search` and
  the calendar through the `gws-secure` wrapper; the note is written to
  `$ORG_DIR/org-roam/daily/YYYY-MM-DD.org` and tagged as Claude-generated
  and unreviewed. After writing the note, if an Emacs server is reachable,
  the file is opened in the user's running Emacs for review.
  Trigger when the user asks to wrap up or record what they did today, or
  for a daily log/standup at end of day, with phrases like "今日のまとめ",
  "今日のラップアップ", "一日のまとめ", "今日やったことまとめて", "日報",
  "日次まとめ", "今日の締め", "daily wrapup", "wrap up my day",
  "today's summary", "今日の活動まとめて".
allowed-tools: Bash(gh search:*), Bash(gh api:*), Bash($CLAUDE_PLUGIN_ROOT/skills/daily-wrapup/fetch-calendar.sh:*), Bash(jq:*), Bash(date:*), Bash(uuidgen:*), Bash(mkdir:*), Bash(git:*), Bash(emacsclient:*)
---

# Daily Wrapup Skill

Wrap up the user's day by summarizing their GitHub activity and today's
events from their own Google Calendar, appending the result to their
org-roam daily note as a Claude-generated, unreviewed subtree, then commit
and push the org repository — but only after the user confirms the commit.
This is the end-of-day counterpart to the `morning-brief` skill. The two
sources are gathered and summarized in parallel by two subagents (calendar
and GitHub), each returning a finished org section.

The daily note lives in a private repository (the user's org), so the note
itself is written in Japanese and may contain real names and titles. This
SKILL.md stays generic and English, and never hardcodes a username or path
(the GitHub login is detected with `gh api user`; the org path comes from
`$ORG_DIR`).

## Prerequisites

- `gh` (GitHub CLI) is authenticated (`gh auth status` succeeds). The search
  covers private repositories the authenticated user can see.
- The calendar section runs `fetch-calendar.sh` (in this skill directory),
  which reads the calendar through `gws-secure`. That requires `gws-secure`
  on `PATH` and bootstrapped (1Password-backed; see
  [`scripts/README.md`](../../../scripts/README.md)) and `op` (1Password CLI)
  signed in. If the script exits non-zero, skip the calendar section and note
  it in one line — never trigger an interactive login from this skill, and
  never fail the whole wrap-up because the calendar could not be read.
- `ORG_DIR` points at the user's org repository (the one that contains
  `org-roam/daily/`). If it is unset, default to `$HOME/org` and, if that is
  not a git work tree, stop and ask the user to export `ORG_DIR`.
- `git`, `jq`, `date`, and `uuidgen` are available on the host. The script
  additionally uses `sed` (host coreutil).

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

### Step 2: Summarize calendar and GitHub in parallel (subagents)

Gather and summarize the two sources concurrently. Spawn two subagents with
the Agent tool **in a single message** so they run in parallel; each one
gathers its own source and returns a finished, Japanese, org-formatted
section, so the raw API JSON never enters the main context. Pass the resolved
`$DAY` (and `$USER_LOGIN` for GitHub) into each prompt verbatim.

**Calendar subagent.** Tell it to:

- Run the calendar fetch script. It reads the user's own primary calendar for
  the day and prints one event per line as `start|end|summary|location`; it
  excludes imported and subscribed calendars, cancelled events, and events
  the user declined (see the script header for the rationale):

  ```bash
  "$CLAUDE_PLUGIN_ROOT/skills/daily-wrapup/fetch-calendar.sh" "$DAY"
  ```

- Format each line as an org bullet for a `** 予定` section: a timed event
  (the `start` field contains a `T`) as `- HH:MM–HH:MM <summary>`, appending
  `@<location>` (preceded by a space) when the location is non-empty; an
  all-day event (no `T`) as `- 終日: <summary>`. Keep chronological order,
  one bullet per event.
- Return **only** those bullet lines. If the script printed nothing, return
  the single token `NO_EVENTS`. If the script exited non-zero (e.g. a
  gws-secure auth failure), return the single token `CALENDAR_UNAVAILABLE`.
  Never invent events.

**GitHub subagent.** Tell it to run these three queries (`gh search` returns
reliable titles and states; the `users/<login>/events` API ships stripped
payloads, so do not use it):

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

Then group by repository and return org subtrees — one `*** owner/repo`
heading per repository with `-` bullets beneath it: lead with the PRs (title
and state, i.e. merged / open / closed) and issues, then fold in the notable
commit subjects. Synthesize, do not dump; drop the wall of
`Merge pull request #N …` commits, since the PR list already covers them. If
all three queries are empty, return the single token `NO_ACTIVITY`.

Wait for both subagents before continuing.

### Step 3: Write the daily org note

Combine the two subagent results. If the calendar returned `NO_EVENTS` or
`CALENDAR_UNAVAILABLE` **and** GitHub returned `NO_ACTIVITY`, there is nothing
to record — tell the user and stop without writing or committing. When the
calendar came back `CALENDAR_UNAVAILABLE`, note that to the user in one line
but still write the GitHub section.

The note is an org-roam daily file. Two cases:

- **File does not exist**: create it with the org-roam node header, then the
  Claude subtree. Lead with the calendar, then GitHub:

  ```org
  :PROPERTIES:
  :ID:       <uuidgen output, uppercase>
  :END:
  #+title: <DAY>
  * <DAY Dow HH:MM> Daily wrapup                                   :claude:
  :PROPERTIES:
  :STATUS:   unreviewed
  :GENERATED_BY: claude-code/daily-wrapup
  :END:

  ** 予定
  - HH:MM–HH:MM <event> @<location>
  - 終日: <event>

  ** GitHub
  *** <owner/repo>
  - …
  ```

- **File already exists**: do not touch the existing header or entries.
  Append the same `* … :claude:` subtree to the end of the file.

Omit a section whose source is empty: write the `** 予定` heading only when
there are events, and the `** GitHub` heading only when there is GitHub
activity. Do not emit an empty heading.

Provenance rules (from the project plan):

- Tag the generated subtree headline `:claude:`. When this skill runs
  unattended (a `claude -p` batch run with no human in the loop), also add
  `:autogenerated:` (org tags cannot contain hyphens, so use
  `autogenerated`, not `auto-generated`).
- Put `:STATUS: unreviewed` in the subtree's property drawer. Review happens
  by editing this tag in org (or by the user telling the skill they reviewed
  it — see Step 4), not through a git PR.
- Generate a fresh `:ID:` with `uuidgen` only when creating a new file;
  never invent or reuse an id for an existing node.

Write the file with the editor tools (not a shell heredoc) so the Japanese
body is handled cleanly.

### Step 4: Confirm, then commit and push the org repo

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

The user signalling that they reviewed the note (e.g. "reviewed",
"review した", "確認した") counts as that explicit yes: treat it as approval
to commit and push, do not ask again. In that case also flip the subtree's
`:STATUS:` from `unreviewed` to `reviewed` before committing (re-stage the
file afterward), since the note has now been reviewed.

On confirmation, commit in English and push the current branch:

```bash
git -C "$ORG_DIR" commit -m "Add daily wrapup for $DAY"
git -C "$ORG_DIR" push || git -C "$ORG_DIR" push -u origin HEAD
```

If the user declines, leave the file written but uncommitted and stop. Do
not commit without an explicit yes.

### Step 5: Open the note in Emacs (best-effort, host-side)

Once the daily file has been written — regardless of whether it was
committed — open it in the user's running Emacs so they can review the
`unreviewed` note in place. This is a convenience, not a requirement: only
attach to an Emacs server that is already running, never start a new Emacs,
and never block waiting for the buffer to close.

```bash
if emacsclient --eval t >/dev/null 2>&1; then
  emacsclient --no-wait "$DAILY_FILE"
fi
```

- `emacsclient --eval t` is a cheap probe: it exits non-zero when no Emacs
  server is running and is "command not found" when `emacsclient` is not
  installed, so the single guard covers both cases. If it fails, skip this
  step silently.
- `--no-wait` opens the buffer and returns immediately instead of blocking
  until the user closes it.
- `emacsclient` talks to the user's host Emacs over a local socket, so (like
  `git` and `gh`) it runs on the host, not in a container.

## Output rules

- The org note body is Japanese and may include real repository names, PR
  titles, commit subjects, and calendar event titles and locations — it
  lives in the private org repo.
- This SKILL.md and the commit message stay English. Never hardcode the
  username or org path; resolve them at run time.
- Synthesize; do not dump every commit. A reader should understand the day
  from a few lines per repository.
- Record only real activity returned by `gh search` and real events returned
  by the calendar API. Do not invent work or meetings.

## Error handling

- `gh` not authenticated: stop and tell the user to run `gh auth login`.
- `fetch-calendar.sh` exits non-zero (gws-secure / 1Password / network), so
  the calendar subagent returns `CALENDAR_UNAVAILABLE`: skip the calendar
  section, record the GitHub activity alone, and note in one line that the
  calendar could not be read. Do not trigger an interactive login, and do not
  fail the whole wrap-up over a calendar error.
- `ORG_DIR` not a git work tree: stop and ask the user to export `ORG_DIR`.
- No calendar events and no GitHub activity for the day: say so and stop
  without writing or committing.
- `git push` fails (no upstream, rejected): report the error and leave the
  commit in place; do not force-push.
- `emacsclient` missing or no Emacs server running: skip opening the note in
  Emacs; this is a convenience step, not an error.

## Out of scope

- Sources other than GitHub and the user's own calendar. Shell history
  (atuin) and Claude Code session logs are planned future sources for this
  skill but are not read yet.
- Calendars other than the user's primary one. Imported and subscribed
  calendars are intentionally excluded.
- A PR flow for the org repo. The daily note is committed directly to the
  org repo's current branch (with confirmation), not via a pull request.
- Mail. Unread inbox triage belongs to the `morning-brief` skill; the
  wrap-up reads the calendar but not mail.

## Security note

GitHub activity is read with the authenticated `gh` CLI on the host and
covers the user's own public and private GitHub activity. Today's calendar
events are read through the `gws-secure` wrapper (see
[`scripts/README.md`](../../../scripts/README.md)), which keeps the OAuth
client and refresh token in 1Password and mints a short-lived access token
in memory on each call — no OAuth token is written to disk — and the read is
scoped read-only to the user's own primary calendar. The skill writes only to
the user's org repository and commits only the single daily file it
generated, after an explicit confirmation.
