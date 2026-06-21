---
name: morning-brief
description: |
  Produce a Japanese morning brief of the user's day from their own
  Google Calendar and Gmail: today's events across all calendars plus
  today's unread inbox mail, triaged and rendered directly in the chat
  so the user reads and engages with it (this is not a hands-off digest
  that gets posted somewhere and forgotten). Calendar and Gmail are read
  through the `gws-secure` wrapper (token-less, 1Password-backed). By
  default the brief is shown in-chat only; posting to Slack is opt-in.
  Trigger when the user asks for a morning brief or what their day looks
  like, with phrases like "今日の予定", "今日のブリーフ", "朝のブリーフ",
  "今日なにある", "今日のメールと予定", "ブリーフ", "morning brief",
  "what's on today", "today's brief".
allowed-tools: Bash(gws-secure calendar:*), Bash(gws-secure gmail:*), Bash(jq:*), Bash(date:*), Bash(base64:*), Bash(tr:*), Bash(mkdir:*), Bash(mktemp:*), Bash(rm:*), Bash($CLAUDE_PLUGIN_ROOT/skills/slack-post/run.sh:*)
---

# Morning Brief Skill

Give the user a fast, scannable Japanese picture of their day from their
own Calendar and Gmail, rendered in the chat response. The brief leads with
today's schedule, then triages today's unread inbox mail (surfacing what
needs action and compressing the rest), and ends by offering to drill into
any item. It does not auto-post anywhere by default — the user is meant to
read it here and engage. This deliberately avoids the hands-off
"summarize-and-post" shape, which the user found does not stick.

Calendar and Gmail are read through the `gws-secure` wrapper, which mints a
short-lived access token from 1Password on each call and never writes an
OAuth token to disk — see [Security note](#security-note).

## Prerequisites

- `gws-secure` is on `PATH` and bootstrapped (the OAuth client and refresh
  token live in the 1Password `googleworkspace cli` item). A
  `gws-secure calendar ...` call must succeed without prompting. See
  [`scripts/README.md`](../../../scripts/README.md).
- `op` (1Password CLI) is signed in. If a `gws-secure` call fails because
  1Password cannot be read, stop and tell the user to run `op signin`
  themselves — never trigger an interactive login from this skill.
- `jq` is available (ships with the host).

## Workflow

### Step 1: Establish today's date

Get the local date once, for labeling the brief and for the Gmail query
window:

```bash
date +%Y-%m-%d
```

### Step 2: Fetch today's calendar agenda

Use the `+agenda` helper, which returns events across all of the user's
calendars in one call:

```bash
gws-secure calendar +agenda --today --format json
```

The response is an object `{ "count", "events", "timeMin", "timeMax" }`.
Each entry in `events` has `calendar`, `summary`, `start`, `end`, and
`location`. `start` and `end` are **plain strings**, not nested objects:
a timed event looks like `2026-06-21T16:15:00-07:00`, and an all-day event
looks like a bare date `2026-06-21` (with `end` the following day). An entry
whose `start` has no `T` is all-day.

Important: `--today` is a rolling **next-24-hours-from-now** window
(`timeMin` = now, `timeMax` = now + 24h), not the local calendar day. Run
later in the day it leaks tomorrow's events. Filter the events down to
today's local date so the brief means "today":

```bash
TODAY="$(date +%Y-%m-%d)"
gws-secure calendar +agenda --today --format json \
  | jq -r --arg d "$TODAY" '.events
      | map(select((.start|startswith($d)) or ((.start < $d) and (.end > $d))))
      | sort_by(.start) | .[]
      | "\(.start)|\(.end)|\(.summary)|\(.location)|\(.calendar)"'
```

The `select` keeps events that start today plus all-day events that span
today (`start < today < end`). If nothing remains, say so in one Japanese
line and continue to the mail section — an empty calendar is not an error.

### Step 3: Fetch today's unread inbox mail

List unread messages that are still in the inbox and arrived recently. Use
`in:inbox` so archived mail is excluded and `newer_than:1d` to scope to the
last day:

```bash
gws-secure gmail users messages list \
  --params '{"userId":"me","q":"is:unread in:inbox newer_than:1d","maxResults":50}' \
  --format json
```

The response lists message ids only. If there are none, say so in one
Japanese line and skip to Step 5 with the calendar-only brief.

For each id, fetch the message and read its headers and snippet. Cache the
large JSON to a file (do not read it into the response) and extract only the
fields the brief needs. Loop with `while IFS= read -r` — a bare
`for id in $ids` does not word-split under zsh and would feed every id to a
single call:

```bash
CACHE_DIR="${MORNING_BRIEF_CACHE_DIR:-$HOME/.cache/claude-private-skills/morning-brief}"
mkdir -p "$CACHE_DIR"

ids="$(gws-secure gmail users messages list \
  --params '{"userId":"me","q":"is:unread in:inbox newer_than:1d","maxResults":50}' \
  --format json | jq -r '(.messages//[])[].id')"

printf '%s\n' "$ids" | while IFS= read -r id; do
  [ -n "$id" ] || continue
  gws-secure gmail users messages get \
    --params "{\"userId\":\"me\",\"id\":\"$id\",\"format\":\"full\"}" \
    --format json > "$CACHE_DIR/$id.json"
  jq -c '{
    from:    ([.payload.headers[] | select(.name=="From")    | .value] | .[0] // ""),
    subject: ([.payload.headers[] | select(.name=="Subject") | .value] | .[0] // "(no subject)"),
    snippet: (.snippet | .[0:100])
  }' "$CACHE_DIR/$id.json"
done
```

Use `format=full` (not `metadata`): the `gws` metadata mode does not pass
the `metadataHeaders` array correctly and returns empty headers. The
`.snippet` field is a short preview — it is enough for triage, so there is
no need to decode the message body for the brief.

### Step 4: Triage the mail

The point is to reduce noise. Pure advertising is dropped entirely, not
shown. Sort each unread message into one of these buckets:

- **要対応 (action needed)**: addressed to the user and expecting a reply,
  action, or decision — a real person writing to them, a request, a
  calendar invite needing a response.
- **🎫 チケット・締切 (tickets / deadlines)**: ticket presales, lotteries
  (抽選), fan-club / お気に入り pre-orders, and on-sale notices that carry a
  **deadline or window** (先行, プレリザーブ, 受付終了, まもなく終了,
  presale, on-sale date). The user explicitly wants these. Always surface
  the deadline/date and what it is for (artist / event).
- **📌 通知 (non-ad notices)**: official, government, security, account,
  shipping, receipt, or transactional notices that are not marketing
  (e.g. a consulate advisory, a bank alert, a delivery update).
- **広告・販促 (ads — dropped)**: marketing blasts, sales, newsletters, and
  generic "buy tickets now" promotions with no deadline. **Do not list
  these.** Show at most a single trailing line with the dropped count
  (e.g. `（広告・販促 N 通は除外）`) so the user knows nothing important was
  hidden.

Judgement call for ticket mail: a real deadline/lottery/presale goes to
🎫; a generic "tickets available" marketing blast with no deadline is an ad
and is dropped. When unsure whether something is an ad or a notice, keep it
in 📌 rather than dropping it.

Lead with 要対応 individually, then 🎫 with deadlines, then 📌. Collapse the
ads to the one-line count.

### Step 5: Render the brief in the chat (Japanese)

Render directly in the chat response. The brief shows the user's real
calendar and mail content — this is their own data shown back to them, so
do not redact event names, senders, or subjects (see
[Output rules](#output-rules)). Keep it short and scannable: a chronological
schedule first, then triaged mail, then an engagement prompt.

```markdown
☀️ **今日のブリーフ（2026-06-21 土）**

📅 **予定（N件）**
- 10:00–11:00 ミーティング名 @場所 〔カレンダー名〕
- 14:00–15:00 …
- 終日: イベント名 〔カレンダー名〕
（予定なしなら「今日の予定はありません。」）

📬 **メール（未読 M 通 / 今日）**
**要対応**
- 差出人 — 件名（一言で要点）
**🎫 チケット・締切**
- 〔締切/先行情報〕 アーティスト/イベント — 何の受付か（例: まもなく受付終了）
**📌 通知**
- 差出人 — 件名（一言で要点）

（広告・販促 K 通は除外）

——
気になるものある？ 詳細を開く・返信を下書き（送信前に確認）・Slackに流す、などできるよ。
```

Rules for the render:

- Order the schedule chronologically; show start–end times, the event
  summary, location if present, and which calendar it came from.
- Mail order: 要対応 first (individually), then 🎫 チケット・締切 (each with
  its deadline/window), then 📌 通知. Drop ads entirely and show only the
  trailing dropped-count line.
- Skip any mail bucket that is empty (do not print an empty heading).
- End with a short engagement line offering next actions (expand an item,
  draft a reply, post to Slack) — do not perform any of them unprompted.

### Step 6 (opt-in): Post to Slack

Only if the user explicitly asks to send the brief to Slack, post the same
rendered markdown via the `slack-post` skill. Write the body to a temp file
and pass it with `--text-file ... --markdown`:

```bash
BRIEF_FILE="$(mktemp /tmp/morning-brief.XXXXXX.md)"
# Write the exact markdown rendered in Step 5 into "$BRIEF_FILE".
"$CLAUDE_PLUGIN_ROOT/skills/slack-post/run.sh" post \
  --text-file "$BRIEF_FILE" --markdown
rm -f "$BRIEF_FILE"
```

Default behaviour is in-chat only. Never post to Slack without being asked.

## Output rules

- The chat brief is in Japanese and shows the user's real calendar/mail
  content (their own data, shown to them) — do not redact it.
- Files stay generic and English: this SKILL.md, and any cached JSON under
  the cache dir, must not be committed and must not hardcode real names,
  addresses, or mailbox ids. Keep PII out of anything that lands in the
  public repository.
- Do not fabricate events or mail. Show only what the API returned; on a
  partial failure, render what succeeded and note what failed in one line.

## Error handling

- 1Password not readable / `gws-secure` auth error: stop and tell the user
  to run `op signin` (or re-run `scripts/gws-secure-bootstrap` if the grant
  was revoked) themselves. This skill must not trigger an interactive login.
- Calendar fetch fails but mail succeeds (or vice versa): render the half
  that worked and note the failure in one Japanese line.
- A single message fails to fetch or parse: skip it, note it, and continue.
- No events and no unread mail: reply that there is nothing for today in one
  Japanese line.

## Out of scope

- Sending mail, replying, or modifying calendar events. Drafting a reply is
  offered as a follow-up but always runs through a separate confirmed flow,
  not this skill.
- A daily org-roam summary written to `daily/`. That is a separate skill;
  this one only briefs the user in the chat (and optionally Slack).
- Newsletters / article summarization (that was `tldr-digest`, dropped).

## Security note

Calendar and Gmail are read through `gws-secure` (see
[`scripts/README.md`](../../../scripts/README.md)), which runs Google's
official `gws` CLI on the host but keeps the OAuth client and refresh token
in 1Password and mints a short-lived access token in memory on each call.
No OAuth token is written to disk. This skill only reads the user's own
Calendar and Gmail; it never modifies them. An opt-in Slack post (Step 6)
runs through the `slack-post` skill, which executes inside a hardened Docker
container with the bot token mounted read-only.
