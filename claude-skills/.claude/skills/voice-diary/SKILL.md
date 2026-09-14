---
name: voice-diary
description: |
  Turn a dictated message into a diary entry in the user's org-roam daily
  note. The user speaks through Claude Code's voice input (the terminal
  dictation, or the Claude app on a phone via /remote-control), so the
  message arrives as raw speech-to-text: no punctuation, filler words,
  run-on sentences, and the occasional misheard word. The skill cleans
  that transcript into readable Japanese prose without changing what the
  user said, appends it to `$ORG_DIR/org-roam/daily/YYYY-MM-DD.org` as a
  timestamped `:voice:` entry (creating the note with an org-roam header
  when the day has none), then commits and pushes the org repository after
  the user confirms, and opens the note in Emacs when a server is reachable.
  Trigger when the user wants to record a diary or journal entry, with
  phrases like "日記", "日記書いて", "日記に追加して", "今日の日記",
  "昨日の日記", "音声で日記", "日記つけて", "org に日記", "ジャーナル",
  "diary", "journal this", "voice diary", "add to my diary". Also trigger
  when a message is clearly a spoken first-person account of the user's
  day and they ask to save or record it, even without the word "diary".
  Do not trigger for end-of-day activity summaries drawn from GitHub or
  the calendar — that is the daily-wrapup skill.
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/voice-diary/append-diary-entry.sh:*), Bash(date:*), Bash(git:*), Bash(emacsclient:*)
---

# Voice Diary Skill

Take the diary the user dictated, clean up the speech-to-text transcript,
and append it to their org-roam daily note as one entry. Then commit and
push the org repository, but only after the user confirms. This is the
free-form counterpart to the `daily-wrapup` skill: daily-wrapup records
what the tools say the user did, voice-diary records what the user says in
their own words.

The daily note lives in a private repository (the user's org), so the entry
is written in Japanese and may name real people, places, and projects. This
SKILL.md stays generic and English, and never hardcodes a path (the org path
comes from `$ORG_DIR`).

## Prerequisites

- `ORG_DIR` points at the user's org repository (the one that contains
  `org-roam/daily/`). If it is unset, default to `$HOME/org` and, if that is
  not a git work tree, stop and ask the user to export `ORG_DIR`.
- `git` and `date` are available on the host. The append script also uses
  `tail`, `grep`, and `tr` (host coreutils), and `uuidgen` when present
  (it falls back to `/proc/sys/kernel/random/uuid` or `python3`).
- The entry is written by `append-diary-entry.sh` (in this skill directory).
  It reads only local org files, needs no network or credentials, and
  therefore runs on the host rather than in a container.

## Workflow

### Step 1: Resolve the day and paths

```bash
ORG_DIR="${ORG_DIR:-$HOME/org}"
DAY="$(date +%Y-%m-%d)"
```

Confirm `ORG_DIR` is a git work tree (`git -C "$ORG_DIR" rev-parse` succeeds);
if not, stop and ask the user to set `ORG_DIR`.

The day defaults to today. Move it only when the user says so:

- "昨日" / "yesterday" → `date -v-1d +%Y-%m-%d` (BSD) or
  `date -d '1 day ago' +%Y-%m-%d` (GNU).
- "一昨日" → two days back, the same way.
- An explicit date ("9月12日の日記") → that date in the current year, or the
  previous year when that date is still in the future.

The entry time is the current clock time (`date +%H:%M`) even for a past
day; the heading records when the entry was dictated, not when the events
happened.

### Step 2: Clean the transcript into a diary entry

The message body is the diary. Produce two things: a short title and a
body. Work from what the user actually said; this is editing, not writing.

Keep:

- The first person, the user's tone, and every fact, name, and opinion
  they voiced. Do not add encouragement, commentary, or facts they did not
  say, and do not summarise content away — a long dictation becomes a long
  entry.
- Japanese as Japanese. Product and tool names stay in their usual spelling
  (`emacs`, `git`, `org-roam`), and spoken English words become that
  English word, not katakana, when the user normally writes them in English.

Change:

- Drop filler words and false starts ("えーと", "あの", "まあ", "なんか",
  "その", "ていうか", repeated words) and self-corrections, keeping the
  corrected version.
- Drop instructions aimed at this skill ("日記に書いて", "昨日の分で",
  "以上") from the body once they have been acted on.
- Add punctuation ("、" and "。"), split run-on speech into sentences, and
  break the body into paragraphs when the topic shifts.
- Turn a spoken enumeration ("一つ目は…二つ目は…") into `-` bullets.
- Write numbers, times, and dates in digits ("3時", "10km", "9月12日").
- Fix a misheard word only when the intended word is obvious from context
  (a homophone that makes no sense as transcribed). When two readings are
  plausible, keep the transcribed one and append `(?)` so the user can fix
  it in Emacs; never guess silently.

The title is a Japanese noun phrase of roughly 10 to 25 characters that
names the main topic ("週末のランニングと膝の様子"), not a full sentence
and not a date, since the heading already carries the timestamp.

Formatting constraints the append script enforces:

- Body lines never start with `*` (that would open a new org heading). Use
  `-` for bullets.
- The body is plain org text: paragraphs separated by one blank line,
  `-` bullets, and nothing else. No property drawers, no `#+` keywords, no
  sub-headings.

When the user dictates several clearly separate topics and asks for them
as separate entries, run Steps 2 and 3 once per entry. Otherwise one
dictation is one entry, with paragraphs marking the topic shifts.

### Step 3: Append the entry to the daily note

Run the append script with the cleaned body on stdin. Quote the heredoc
delimiter so the Japanese body passes through untouched:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/voice-diary/append-diary-entry.sh" "$DAY" "<title>" <<'BODY'
<cleaned body>
BODY
```

The script prints the path of the daily note. It creates the note with the
org-roam header when the day has none, otherwise appends after a blank
line, and never rewrites existing content. The result looks like:

```org
* <2026-08-15 Sat 12:29> 週末のランニングと膝の様子 :voice:
朝、いつものコースを10km走った。先週痛かった右膝は今日は問題なし。

来週からは距離を12kmに伸ばしてみる。
```

The heading shape (`* <YYYY-MM-DD Dow HH:MM> title`) matches the user's
Emacs capture template, so a dictated entry sits next to typed ones
without standing out; the `:voice:` tag is the only marker.

If the script exits non-zero, show its error message, fix the body (the
usual cause is a bullet written with `*`), and run it again. Do not fall
back to writing the file by hand.

### Step 4: Confirm, then commit and push the org repo

Stage only the daily note — never `git add .`:

```bash
git -C "$ORG_DIR" add "org-roam/daily/$DAY.org"
BRANCH="$(git -C "$ORG_DIR" branch --show-current)"
```

Then show the user, in Japanese, the entry exactly as written (title and
body) together with the day and the target branch (`$BRANCH`), and ask
plainly whether to commit and push (e.g. `org に commit & push していい？`).
Wait for an explicit yes. The org repo may be on a non-default branch —
name the branch in the prompt so the user can catch it; if they want it on
`main`, they switch the org repo themselves first.

The user will often answer by voice, so accept corrections in the same
breath: if they change a word, add a sentence, or ask to drop one, edit
the entry in the daily note with the editor tools, re-stage the file, show
the corrected entry, and ask again. An answer such as "それでいい",
"OK", "push して" counts as the yes.

On confirmation, commit in English and push the current branch:

```bash
git -C "$ORG_DIR" commit -m "Add voice diary entry for $DAY"
git -C "$ORG_DIR" push || git -C "$ORG_DIR" push -u origin HEAD
```

If the user declines, leave the note written but uncommitted and stop. Do
not commit without an explicit yes.

### Step 5: Open the note in Emacs (best-effort, host-side)

Once the note has been written — committed or not — open it in the user's
running Emacs so they can read the entry in place. Only attach to an Emacs
server that is already running, never start a new Emacs, and never block
waiting for the buffer to close:

```bash
if emacsclient --eval t >/dev/null 2>&1; then
  emacsclient --no-wait "$ORG_DIR/org-roam/daily/$DAY.org"
fi
```

`emacsclient --eval t` exits non-zero when no server is running and is
"command not found" when `emacsclient` is not installed, so the single guard
covers both cases. If it fails, skip this step silently. `emacsclient`
talks to the host Emacs over a local socket, so it runs on the host, not in
a container.

## Output rules

- The entry body is Japanese in the user's own voice and may include real
  names, places, and project names — it lives in the private org repo.
- This SKILL.md and the commit message stay English. Never hardcode the org
  path; resolve it at run time.
- Record only what the user said. Do not invent details, and do not soften
  or reword opinions.
- The chat reply after writing is short: the entry as written, the branch,
  and the confirmation question. Do not restate the transcript.

## Error handling

- `ORG_DIR` not a git work tree: stop and ask the user to export `ORG_DIR`.
- `append-diary-entry.sh` reports a missing daily directory: the org repo
  is not the one expected; stop and ask the user to check `ORG_DIR`.
- `append-diary-entry.sh` rejects the body (empty, or a line starting with
  `*`): fix the body and rerun; nothing was written.
- The dictation is empty or is only an instruction ("日記書いて" with no
  content): ask the user what to write, and do not create a note.
- `git push` fails (no upstream, rejected): report the error and leave the
  commit in place; do not force-push.
- `emacsclient` missing or no Emacs server running: skip opening the note;
  this is a convenience step, not an error.

## Out of scope

- Summarising the day from GitHub, the calendar, or shell history. That is
  the `daily-wrapup` skill.
- Editing or deleting earlier entries in the daily note. The script only
  appends; the user edits older entries in Emacs.
- Promoting an entry into a standalone org-roam node. The org repo's
  `org-graduate` skill does that from the dailies later.
- A PR flow for the org repo. The entry is committed directly to the org
  repo's current branch (with confirmation), not via a pull request.

## Security note

The skill touches no network service and reads no credentials. The append
script runs on the host because it only writes one local org file, and
`git` and `emacsclient` run on the host because they talk to the user's
local repository and Emacs socket. The skill commits only the single daily
note it wrote, after an explicit confirmation.
