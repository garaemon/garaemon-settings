---
name: org-graduate
description: |
  Scan recent org-roam daily notes and produce a graduation proposal:
  which daily entries should seed new org-roam nodes, and which should be
  appended as log entries to existing nodes. Phase 1 is read-only
  (dry-run): the skill outputs a markdown proposal for user review and
  writes no files. The workflow is for dailies-first users who capture
  thoughts in daily notes but rarely author standalone roam nodes — the
  skill surfaces what is worth graduating so the user and Claude can
  curate together.
  Trigger when the user asks to extract, promote, or graduate content
  from dailies into roam nodes, or says things like "daily から roam
  育てて", "graduate dailies", "週次で roam 整理", "dailyから昇格候補探して",
  "organize this week's dailies".
---

# Org Graduate Skill (Phase 1: dry-run)

Scan recent `org-roam-dailies` entries, match them against existing
org-roam nodes, and produce a graduation proposal — a markdown report
that lists candidate entries and whether each should append to an
existing node or seed a new one. This skill does NOT write any files in
Phase 1; the apply step comes in a later phase.

## Prerequisites

- `sqlite3` is installed and the org-roam DB exists.
- A config file at `~/.config/org-graduate/config.toml` tells the skill
  where the org directory and roam DB live. A minimal config:

  ```toml
  org_dir = "/home/garaemon/ghq/github.com/garaemon/org"
  roam_dir = "/home/garaemon/ghq/github.com/garaemon/org/org-roam"
  daily_dir = "/home/garaemon/ghq/github.com/garaemon/org/org-roam/daily"
  roam_db = "/home/garaemon/.emacs.d/org-roam.db"
  screen_tags = ["@work"]
  default_since_days = 7
  ```

  `screen_tags` marks contexts whose entries need a stricter reusability
  check before graduation (see Step 5 and Step 7). It is not a hard
  skip — entries under these tags are kept if they carry generalisable
  knowledge.

  If the file is missing, stop and print the example above. Do not
  invent defaults; the paths are host-specific.

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

To apply: re-run with `--apply` (Phase 2, not yet implemented).
```

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

## Out of scope (Phase 1)

- Writing anything under `org_dir`.
- Running `emacs --batch` or `org-roam-db-sync`.
- Creating git branches, commits, or PRs.
- Modifying the daily file to mark entries as "graduated".

Those actions belong to Phase 2.

## Error handling

- Config file missing or malformed → stop; print the example config.
- Any path in the config does not exist → stop; ask the user to fix
  the config.
- Roam DB exists but query fails (e.g., schema mismatch after an
  org-roam upgrade) → show the sqlite error verbatim and stop.
- Zero dailies in the window → print the window info, report zero
  entries, and stop without widening the window.
