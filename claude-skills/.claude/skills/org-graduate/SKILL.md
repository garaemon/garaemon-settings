---
name: org-graduate
description: |
  Scan recent org-roam daily notes and produce a graduation proposal:
  which daily entries should seed new org-roam nodes, and which should
  be appended as log entries to existing nodes. The skill runs in two
  phases. Dry-run always runs first: it outputs a markdown proposal
  for user review without touching any file. Apply mode (opt-in, only
  when the user explicitly asks) then creates the proposed `.org`
  files, runs `org-roam-db-sync`, and opens a pull request against the
  configured org repository using a bot identity. The workflow is for
  dailies-first users who capture thoughts in daily notes but rarely
  author standalone roam nodes — the skill surfaces what is worth
  graduating so the user and Claude can curate together, then handles
  the mechanical graph-maintenance once the user approves.
  Trigger when the user asks to extract, promote, or graduate content
  from dailies into roam nodes, or says things like "daily から roam
  育てて", "graduate dailies", "週次で roam 整理", "dailyから昇格候補探して",
  "organize this week's dailies". Also trigger on follow-up phrases
  like "apply this", "これで作って", "PR出して" once a proposal is
  already in the chat.
---

# Org Graduate Skill

Scan recent `org-roam-dailies` entries, match them against existing
org-roam nodes, and produce a graduation proposal — a markdown report
that lists candidate entries and whether each should append to an
existing node or seed a new one. The skill has two modes:

- **Dry-run** (Steps 1–8): always runs first. Reads dailies and the
  roam DB, judges each entry, and prints a proposal. No file writes,
  no git operations.
- **Apply** (Steps 9–16, optional): only runs when the user approves
  the dry-run proposal and explicitly asks to apply. Creates or edits
  `.org` files, runs `org-roam-db-sync`, commits with a bot identity,
  pushes, and opens a PR against the configured org repo.

Apply mode operates on `$org_dir` (a separate git repo), never on the
skill's own repo.

## Prerequisites

### Dry-run mode

- `sqlite3` is installed and the org-roam DB exists.

### Apply mode (in addition)

- `uuidgen` is installed (used to generate node IDs in the
  existing uppercase-hyphenated format).
- `emacs --batch` can load the user's `init.el` and has `org-roam`
  available, so that `(org-roam-db-sync)` resolves.
- `git` is installed and `$org_dir` is a clean git repo with a remote.
- `gh` (GitHub CLI) is authenticated and able to open PRs against the
  configured remote.

### Config

A config file at `~/.config/org-graduate/config.toml` tells the skill
where the org directory and roam DB live, plus the bot identity used
for apply-mode commits. A minimal config:

```toml
org_dir = "/home/garaemon/ghq/github.com/garaemon/org"
roam_dir = "/home/garaemon/ghq/github.com/garaemon/org/org-roam"
daily_dir = "/home/garaemon/ghq/github.com/garaemon/org/org-roam/daily"
roam_db = "/home/garaemon/.emacs.d/org-roam.db"
screen_tags = ["@work"]
default_since_days = 7

# Apply mode only
bot_name = "garaemon-bot"
bot_email = "garaemon+githubbot@gmail.com"
pr_remote = "origin"
pr_base_branch = "main"
```

`screen_tags` marks contexts whose entries need a stricter
reusability check before graduation (see Step 5 and Step 7). It is
not a hard skip — entries under these tags are kept if they carry
generalisable knowledge.

`bot_name` / `bot_email` are the git identity used for apply-mode
commits. They do NOT replace the user's global git config; the skill
sets them per-commit via `GIT_COMMITTER_*` / `GIT_AUTHOR_*` env vars.

`pr_remote` / `pr_base_branch` point at the remote and base branch
of the org repo to push the feature branch to and open the PR
against.

If the config file is missing, stop and print the example above. Do
not invent defaults; the paths are host-specific. Apply-mode-only
fields are optional when the user is only running dry-run.

## Inputs

The user may specify a date window. Interpret intent as follows:

- "last week" / "since N days" → that many days back to today.
- "yesterday" / "since 1 day" → 1 day back.
- An explicit date range → use verbatim.

Absent any hint, use `default_since_days` from config.

## Workflow

### Step 1: Load config

Read `~/.config/org-graduate/config.toml` with the `Read` tool. The
format is flat TOML: extract `org_dir`, `roam_dir`, `daily_dir`,
`roam_db`, `screen_tags` (array of strings), and `default_since_days`
(integer).

Verify every path exists before proceeding. If any is missing or the
config file is absent, stop and surface the error together with the
example config from Prerequisites.

### Step 2: Resolve the date window

Compute `SINCE` and `UNTIL` as `YYYY-MM-DD`. Default `UNTIL` is today
(from `date +%Y-%m-%d`).

```bash
SINCE=$(date -d "N days ago" +%Y-%m-%d)
UNTIL=$(date +%Y-%m-%d)
```

`N` comes from the user's hint or `default_since_days`. On BSD `date`
(macOS), use `date -v-Nd +%Y-%m-%d` instead.

### Step 3: List candidate daily files

Daily filenames follow `YYYY-MM-DD.org`. Ignore `*.org_archive`.

```bash
ls "$daily_dir" | awk -v since="$SINCE" -v until="$UNTIL" \
  '/^[0-9]{4}-[0-9]{2}-[0-9]{2}\.org$/ {
     base=substr($0, 1, 10);
     if (base >= since && base <= until) print;
   }'
```

If zero files fall in the window, report that and stop. Do not widen
the window silently.

### Step 4: Parse each daily file

Read the file with `Read`. Each top-level `*` heading (one asterisk
at column zero, followed by a space) is one entry. Collect:

- `heading`: the heading line minus leading stars.
- `timestamp`: the `<YYYY-MM-DD ...>` bracket if present in the heading.
- `tags`: the trailing `:tag1:tag2:` suffix if present.
- `body`: lines from the heading (inclusive) up to, but not including,
  the next top-level `*` heading. Sub-headings (`**`, `***`) stay in
  the body.
- `entry_id`: if a `:PROPERTIES:` drawer with `:ID:` immediately
  follows the heading, capture it so the proposal can reference it as
  `[[id:...]]`. If absent, reference the daily file node's `:ID:` (at
  the top of the daily `.org` file) as the fallback source link.

### Step 5: Flag screen-tagged entries

An entry is "screened" if its tag list intersects `screen_tags`, or if
its only ancestor heading within the daily carries one of those tags
(because users often put the context tag on the top-level daily
heading only, not on each sub-entry). Screened entries are **not**
dropped here. They continue through the same candidate-finding and
judgment steps as normal entries, but in Step 7 they must pass an
extra reusability bar to be graduated.

Track which entries are screened so the final report can annotate them
(and the skipped list can cite "failed screen reusability bar" when
applicable).

### Step 6: Find related roam nodes for each surviving entry

Use the roam DB. Note: org-roam stores `id`, `title`, and `tag` values
with surrounding double quotes, so strip them with
`replace(col, '"', '')` in every query.

List all file-level nodes (use this as the master title table):

```bash
sqlite3 "$roam_db" <<'SQL'
SELECT replace(n.id, '"', '')    AS id,
       replace(n.title, '"', '') AS title,
       n.file                    AS file
FROM nodes n
WHERE n.level = 0
ORDER BY title;
SQL
```

Lookup by title or alias (substring match):

```bash
sqlite3 "$roam_db" <<SQL
SELECT DISTINCT replace(n.id, '"', ''), replace(n.title, '"', '')
FROM nodes n
LEFT JOIN aliases a ON n.id = a.node_id
WHERE replace(n.title, '"', '') LIKE '%${TERM}%' COLLATE NOCASE
   OR replace(a.alias, '"', '') LIKE '%${TERM}%' COLLATE NOCASE;
SQL
```

Also run the `Grep` tool against `$roam_dir` (glob `*.org`) for
content-level matches on keywords you lift from the entry body. The DB
gives titles and aliases; Grep catches topics mentioned inside a node
body but not in its title.

### Step 7: Judge each entry

For each candidate entry, decide one of:

- `append_to_existing` — the entry is a follow-up on a topic an
  existing node already covers (e.g., a new log line under an
  existing tool or concept node). Record the target node id and title.
- `create_new` — the entry introduces a stable topic that deserves its
  own node. Suggest a filename `YYYYMMDDHHMMSS-slug.org`, a `#+title:`,
  and `#+filetags:` based on the entry content.
- `skip` — the entry is too short, too ephemeral, or too tightly
  scoped to a single day to be worth graduating.

Heuristics:

- Same topic reappearing across multiple dailies → strong signal to
  graduate (as `append_to_existing` if a node already exists, else
  `create_new`).
- A `DONE` entry with a reflection paragraph → often worth capturing
  the learning as a log line under the relevant node.
- A one-line "meeting note" with no narrative → usually `skip`.
- When unsure between `append_to_existing` and `create_new`, prefer
  `append_to_existing` — a smaller graph beats an orphan-heavy graph.

#### Extra rules for screened entries

Screened entries (those flagged in Step 5) must additionally pass a
**reusability bar** before being graduated. The goal is to salvage
generalisable knowledge that happens to have been captured in a
screened context (e.g. technical notes tucked under a `:@work:`
Morning-Brainstorming heading), without leaking context-specific
details that belong only in the original setting.

A screened entry **may** be graduated if:

- It is about a tool, technique, design decision, or troubleshooting
  insight that makes sense outside the screened context.
- It does not structurally depend on a specific person's name, an
  internal project/product codename, a team-internal schedule, or
  confidential context to convey its point.
- After generalisation (below), it still reads as a coherent note.

A screened entry **must be skipped** if any of the following apply:

- It is a 1-on-1 or meeting note whose value depends on who was there
  (a named colleague's 1-on-1, a named reviewer's session).
- It is a status update on an internal project referenced by its
  codename, a customer-specific engagement, or team-internal context.
- Generalising it would strip so much that the remaining note is
  trivial or incoherent.

**Generalisation rule.** When graduating a screened entry:

- Remove personal names. If the learning is actually "during a 1-on-1,
  do X", keep the pattern and drop the name. If the note is
  fundamentally about a specific person's behaviour or situation, skip
  instead.
- Remove or abstract internal project/product codenames: drop any
  sentence whose meaning depends on knowing an internal codename,
  customer name, or team-only context. Publicly known tool and
  technology names (OSS tools, widely known commercial products, and
  public-domain techniques such as `git`, `node`, `mermaid`, `GitHub`)
  stay as-is — they are public knowledge.
- Preserve the original Japanese wording of the salvaged content where
  possible; only the context-specific bits are stripped.

In the proposal report, annotate graduated-from-screened entries with
`(from screened entry)` next to the source line so the user can
double-check the generalisation.

### Step 8: Render the proposal

Print a single markdown report to the chat. Structure:

```markdown
# org-graduate proposal (dry-run)

- Window: YYYY-MM-DD to YYYY-MM-DD (N days)
- Dailies scanned: K
- Entries considered: M (of which S were screened via screen_tags)

## Append to existing node

### <Node title> — `[[id:NODE-UUID]]`
File: `<roam-file>`
Source: `daily/YYYY-MM-DD.org` entry "<heading>"
Proposed addition to the node's `* 事象ログ` section (create the
section if it does not yet exist):

~~~org
** <YYYY-MM-DD> <heading text>
from [[id:SOURCE-ID][YYYY-MM-DD]]
<short body excerpt or distilled takeaway, in Japanese>
~~~

## Create new node

### Title: `<title>`
Suggested filename: `YYYYMMDDHHMMSS-slug.org`
Suggested filetags: `:tag1:tag2:`
Source daily entries:
- `daily/YYYY-MM-DD.org` "<heading>"
- (further dailies if the same topic appears more than once)

Proposed body:

~~~org
:PROPERTIES:
:ID:       <generate when applied>
:END:
#+title: <title>
#+date: <today>
#+filetags: :tag1:tag2:

* 概要
<two or three sentence summary distilled from the source entries, in Japanese>

* 事象ログ
** <YYYY-MM-DD> <heading text>
from [[id:SOURCE-ID][YYYY-MM-DD]]
<short body excerpt or distilled takeaway, in Japanese>
~~~

## Skipped

- `daily/YYYY-MM-DD.org` "<heading>" — <reason, e.g. single-line
  meeting note, screened (@work) and failed reusability bar, too
  scoped to a single day>
- ...

## Next steps

To apply: ask Claude to apply this proposal (see Apply mode below).
Claude will confirm the scope with you before writing any files.
```

## Apply mode

After Step 8 has produced a dry-run proposal in the chat, the user
may ask to apply it (triggers include "apply", "これで作って",
"PR出して"). Apply mode modifies the `$org_dir` git repo on disk: it
creates and edits `.org` files, runs `org-roam-db-sync`, commits with
the bot identity, pushes the branch, and opens a pull request.

Every git operation in this section targets `$org_dir` via
`git -C "$org_dir" ...`. The only place the skill changes directory
is when invoking `gh pr create`, so the CLI picks up the org repo's
remote. Never run git commands in the skill's own repo as part of
apply mode.

### Step 9: Confirm the apply scope

The dry-run proposal may list several `append_to_existing` and
`create_new` items. The user may want to apply only a subset (for
example, "just the new node, not the log append"). Before proceeding:

1. Summarise the proposed writes as a short bullet list (one line
   per item: action, node title, source daily).
2. Ask the user to confirm: apply all, apply a subset (which?), or
   cancel.
3. Lock the agreed subset as the apply set for the rest of the
   steps. Items outside the apply set must not be written.

If the user cancels or does not respond affirmatively, stop without
touching any file.

### Step 10: Verify org repo preconditions

Fail fast on any of the following. Surface the exact check that
failed and stop; do not attempt auto-recovery.

```bash
git -C "$org_dir" rev-parse --git-dir >/dev/null                 # must be a git repo
[[ -z "$(git -C "$org_dir" status --porcelain)" ]]                # working tree clean
git -C "$org_dir" fetch "$pr_remote" "$pr_base_branch"             # refresh base
git -C "$org_dir" checkout "$pr_base_branch"                       # switch to base
git -C "$org_dir" pull --ff-only "$pr_remote" "$pr_base_branch"    # sync base
```

If the working tree is dirty, do NOT stash — the user's in-progress
edits may be valuable. Stop and ask the user to commit or shelve
them first.

Branch name: `YYYY.MM.DD-org-graduate` using today's date. Fail if
it already exists on the local or remote side:

```bash
new_branch="$(date +%Y.%m.%d)-org-graduate"
if git -C "$org_dir" show-ref --quiet "refs/heads/$new_branch" \
|| git -C "$org_dir" ls-remote --exit-code --heads "$pr_remote" "$new_branch" >/dev/null 2>&1; then
  die "Branch $new_branch already exists. Delete or rename before retrying."
fi
```

### Step 11: Generate UUIDs, timestamps, and slugs

For each `create_new` item in the apply set:

- UUID: `uuidgen | tr 'a-z' 'A-Z'` — match the uppercase-hyphenated
  format used by the existing corpus.
- Filename timestamp: `date +%Y%m%d%H%M%S`.
- Slug: lowercase the title, replace spaces with `_`, strip any
  characters other than alphanumerics, `_`, `-`, and CJK. Example:
  `nanoclaw` stays `nanoclaw`; `org mode workflow` becomes
  `org_mode_workflow`.
- Full path: `$roam_dir/${timestamp}-${slug}.org`.

Record the `{title → uuid}` mapping so that cross-references inside
proposed bodies (e.g. a new node linking to another new node being
created in the same run) resolve to the same generated UUID.

### Step 12: Create the feature branch

```bash
git -C "$org_dir" checkout -b "$new_branch"
```

All subsequent writes happen on this branch.

### Step 13: Write files

For each `create_new` item:

1. Build the body from the proposal template, substituting the
   generated UUID into the `:ID:` line and replacing any placeholder
   `<generate when applied>` tokens (including cross-links) with the
   corresponding UUID.
2. Set `#+date:` to today in `<YYYY-MM-DD Ddd>` format.
3. Write the file at `$roam_dir/${timestamp}-${slug}.org`. Fail if
   the file already exists (extremely unlikely with a timestamped
   name, but the safety check is cheap).

For each `append_to_existing` item:

1. Read the target file from the DB row (`n.file`).
2. Find the `* 事象ログ` top-level heading. If absent, append a new
   `* 事象ログ` heading at the end of the file, preceded by a blank
   line.
3. Append the proposed `** <YYYY-MM-DD> <heading>` block under the
   `* 事象ログ` section, at the end of that section (before the next
   top-level heading if any, otherwise at end of file).
4. Preserve the file's existing content, line endings, indentation,
   and trailing newline. Edit in place using the `Edit` tool so the
   diff is minimal.

### Step 14: Run org-roam-db-sync

After all file writes, refresh the roam DB so the committed branch
state matches Emacs's view:

```bash
emacs --batch -l ~/.emacs.d/init.el --eval '(org-roam-db-sync)' 2>&1
```

If the command exits non-zero or prints an org-roam error, stop and
surface the full output verbatim. Do NOT roll back the file changes —
the branch contains uncommitted edits that the user may want to
inspect. Recommend that the user fix their Emacs config and re-run
sync manually, or drop the branch with
`git -C "$org_dir" checkout $pr_base_branch && git -C "$org_dir" branch -D $new_branch`.

### Step 15: Commit and push

Stage only the roam files the apply set touched. Never use
`git add -A`, `git add .`, or `git add <dir>` — stage each file
explicitly so unrelated files (e.g. org-roam DB caches, backup
`~` files, dailies that got auto-committed during the run) are not
swept in.

```bash
git -C "$org_dir" add "$roam_dir/${timestamp}-${slug}.org"  # for each create_new
git -C "$org_dir" add "<existing-node-file>"                # for each append_to_existing

GIT_COMMITTER_NAME="$bot_name" \
GIT_COMMITTER_EMAIL="$bot_email" \
GIT_AUTHOR_NAME="$bot_name" \
GIT_AUTHOR_EMAIL="$bot_email" \
  git -C "$org_dir" commit -m "$(cat <<'MSG'
org-graduate: apply proposal YYYY-MM-DD

- <one bullet per item, e.g. "add node nanoclaw", "append log entry to org-mode">

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"

git -C "$org_dir" push -u "$pr_remote" "$new_branch"
```

The bot identity is applied per-commit via env vars so the user's
global git config stays untouched.

### Step 16: Open the PR and report the URL

```bash
cd "$org_dir"
gh pr create \
  --base "$pr_base_branch" \
  --title "org-graduate: apply proposal $(date +%Y-%m-%d)" \
  --body "$(cat <<BODY
## Summary

<bulleted list of applied items, mirroring the commit message>

## Source dailies

<list of daily files cited by the applied items>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

Report the resulting PR URL to the user in the chat reply. That is
the end of apply mode — the user takes over for review and merge.

## Output rules

- The proposal report itself (section headers, meta lines) stays in
  English. Claude's surrounding chat reply may be in Japanese per the
  user's preference.
- **All generated org content is written in Japanese**, matching the
  user's existing dailies and roam nodes. This covers:
  - Section headings in proposed node bodies (use `* 概要`, `* 事象ログ`,
    not `* Summary`, `* Log`).
  - Distilled takeaways and summaries that Claude authors.
  - `#+title:` values when the concept has a natural Japanese name;
    keep public proper nouns, product names, and tool names in their
    native spelling (e.g. `ros`, `docker`).
  - `#+filetags:` values follow the existing corpus: short romaji or
    English tokens like `:tool:`, `:org:`, `:work:` are fine.
- Preserve the original Japanese from the daily entry when quoting
  excerpts — do not translate into English.
- **Do not emit internal codenames, customer names, colleague personal
  names, or other context that is meaningful only inside the screened
  setting.** This applies to both proposed node bodies and proposal
  metadata (titles, filenames, tags, log summaries). When in doubt,
  skip the entry rather than partially generalise.
- Every proposed write is shown in full org syntax so the user can
  review it before any file is touched.
- Do not fabricate node IDs. For `create_new` proposals, write
  `:ID:       <generate when applied>` verbatim as a placeholder.

## Out of scope

- Modifying the daily file to mark entries as "graduated" (e.g.
  annotating that a sub-entry was promoted into a roam node). This
  may land in a future phase; for now the daily stays untouched as
  the authoritative source-of-capture.
- Operating on more than one `$org_dir` in a single invocation. The
  config is single-profile; invoke the skill separately with a
  different config path for a second profile.
- Merging the PR. The skill stops after `gh pr create`; the user
  reviews and merges.

## Error handling

### Dry-run

- Config file missing or malformed → stop; print the example config.
- Any path in the config does not exist → stop; ask the user to fix
  the config.
- Roam DB exists but query fails (e.g., schema mismatch after an
  org-roam upgrade) → show the sqlite error verbatim and stop.
- Zero dailies in the window → print the window info, report zero
  entries, and stop without widening the window.

### Apply

- `uuidgen`, `emacs --batch`, `git`, or `gh` is missing → stop and
  ask the user to install it; do not try an alternative binary.
- Apply-mode config field missing (`bot_name`, `bot_email`,
  `pr_remote`, `pr_base_branch`) → stop with a clear message naming
  the missing key.
- `$org_dir` working tree is dirty → stop; ask the user to commit
  or shelve changes.
- Branch name already exists locally or on the remote → stop; ask
  the user to delete or rename.
- `$pr_base_branch` cannot be fast-forwarded from the remote → stop;
  ask the user to reconcile manually.
- `org-roam-db-sync` fails after file writes → surface output,
  leave the branch in place for the user to inspect. Do NOT roll
  back. Do NOT commit or push in this state.
- `git commit` / `git push` / `gh pr create` fails → surface the
  error, stop, and report the current local branch state so the
  user can recover (the uncommitted or unpushed work is still on
  disk).
