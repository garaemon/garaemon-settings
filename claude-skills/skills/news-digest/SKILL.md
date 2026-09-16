---
name: news-digest
description: |
  Produce a morning news digest for a given topic (AI, software, NBA, ...),
  with web-searched headlines, category grouping, and cross-day
  deduplication against a persistent history file. The skill is
  parameterized by a topic name; each topic ships as a small markdown
  config under `topics/<name>.md` that defines the search queries,
  category buckets, header emoji, and history filename. Add a new topic
  by dropping in a new file — no code change needed.
  Trigger when the user asks for a morning or daily news digest on a
  configured topic, or says things like "今日のAIニュース",
  "software news まとめて", "NBAニュース教えて",
  "morning AI digest", "daily software news", "news-digest ai".
allowed-tools: Bash(date:*), Bash(mkdir:*), WebSearch, WebFetch
---

# News Digest Skill

Compose a short Japanese morning digest of today's news for a single
topic. The skill follows the same skeleton for every topic — resolve
the date, load the topic config, read the dedup history, run targeted
web searches, drop items already in history, format the result, and
append today's items back to history.

Per-topic detail (search queries, category buckets, header emoji,
history filename) lives in `topics/<topic>.md`. The skill itself is
topic-agnostic.

## Arguments

The skill expects one positional argument: the topic name, which must
correspond to a file at
`$CLAUDE_PLUGIN_ROOT/skills/news-digest/topics/<topic>.md`.

If no argument is given, list the available topics (by reading the
`topics/` directory) and ask which one to run. If the argument does not
match a topic file, print the list of available topics and stop — do
not guess.

## Prerequisites

- Network access is available for web searches.
- A writable history directory. By default:
  `~/.cache/claude-private-skills/news-history/`. Override with the
  `NEWS_DIGEST_HISTORY_DIR` environment variable if set.

## Workflow

### Step 1: Resolve the topic and config

Read `topics/<topic>.md`. The file uses YAML frontmatter with these
keys:

- `emoji`: single emoji shown in the header (e.g. `🤖`).
- `label_ja`: Japanese label used in the header (e.g. `AIニュース`).
- `history_file`: filename under the history directory (e.g.
  `ai-news.md`).
- `history_limit`: max entries retained in history (e.g. `100`).
- `queries`: list of web-search query templates. `{today}` is
  substituted with today's date in `YYYY-MM-DD`.
- `categories`: ordered list of `{ emoji, label_ja, hint }` objects
  describing the category buckets to group items under. `hint` is a
  short Japanese description of what falls in this bucket, used only
  to guide grouping.
- `scope_ja`: one Japanese sentence describing what counts as in-scope
  (e.g. "AI の主要企業・ライブラリ・研究・政策"). Used to decide
  what to include.
- `exclude_ja` (optional): one Japanese sentence describing what to
  exclude (e.g. "AI 関連は除外"). Used to keep adjacent topics from
  overlapping.

The body of the topic file is free-form Japanese prose shown to the
reader of the config but not parsed by the skill.

If a key is missing, surface the error and stop.

### Step 2: Resolve today's date and history paths

```bash
TODAY=$(date +%Y-%m-%d)
HISTORY_DIR="${NEWS_DIGEST_HISTORY_DIR:-$HOME/.cache/claude-private-skills/news-history}"
mkdir -p "$HISTORY_DIR"
```

The full history path is `"$HISTORY_DIR/$history_file"` (from the
topic config).

On macOS the default `date` works the same; no BSD-specific flags are
required at this step.

### Step 3: Load the dedup history

If the history file exists, read it and collect every URL and title
seen so far. If it does not exist, treat the set as empty.

History file format — one entry per line:

```text
YYYY-MM-DD<TAB><Title><TAB><URL>
```

Do not parse dates beyond the first column; the file is used as a
flat dedup set.

### Step 4: Run topic-scoped web searches

For each query template in `queries`, substitute `{today}` with
`$TODAY` and run a `WebSearch`. Stop early once you have enough
headlines — usually 2–4 searches is plenty. From the combined
results, keep only items that:

1. Match `scope_ja` (in scope for this topic).
2. Are not excluded by `exclude_ja` (if present).
3. Are actually dated today or within the last 24 hours (read the
   snippet or fetch the page with `WebFetch` when the date is
   ambiguous).
4. Have an actual source URL (no bare aggregator links).

Fabrication is disallowed. If no headline can be grounded in a real
search result, report that there is nothing new for today.

### Step 5: Dedupe against history

Drop any item whose URL or title already appears in the history set
from Step 3. Normalise URLs minimally (strip `utm_*` and `#fragment`)
before comparing. Do not paraphrase titles before matching — an
exact-ish title hit is enough to treat as seen.

If zero items remain after dedup, stop and respond with a single
Japanese line: `本日の新着 <label_ja> はありません（YYYY-MM-DD）。`
Do not update the history file in this case.

### Step 6: Group into categories

For each remaining item, assign it to one of the categories defined
in `categories` using the `hint` fields. If an item fits none of the
buckets, put it under a trailing `その他` category.

Preserve the order of `categories` in the config. Within a category,
keep items in the order they were collected.

### Step 7: Render the digest in Japanese

Output a Japanese markdown digest in the chat response with this
structure:

```markdown
{emoji} **今日の{label_ja}（YYYY-MM-DD）**

**{category.emoji} {category.label_ja}**

**1. 短いタイトル**
2〜4 文の内容説明。
🔗 https://source.example/article

**2. …**
```

Rules:

- The chat response is in Japanese. This SKILL.md and files written
  stay in English.
- Every item must include a real source URL.
- Keep each item to 2–4 Japanese sentences — the user reads this at
  breakfast.
- If a category has no items, skip its heading.

### Step 8: Append to the history file

Append one line per delivered item to the history file in the format
from Step 3 (`YYYY-MM-DD<TAB>Title<TAB>URL`). After appending, if the
file exceeds `history_limit` lines, truncate to the most recent
`history_limit` lines (`tail -n $history_limit`).

If Step 5 produced zero items, skip this step entirely.

## Output rules

- Chat response is in Japanese; files (SKILL.md, topic configs,
  history) stay in ASCII / English identifiers except for the
  `*_ja` fields.
- Only report items returned by the web searches. Do not invent or
  backfill from model memory.
- Only one topic per invocation. To cover multiple topics, invoke
  the skill once per topic.

## Error handling

- Unknown topic: print the list of available topics and stop.
- Missing required key in `topics/<topic>.md`: surface the specific
  missing key and stop.
- Web search rate-limited or empty: proceed with whatever was
  returned; if nothing is left after dedup, emit the "新着なし" line.
- History directory not writable: surface the path and the error;
  do not silently skip the append step.

## Out of scope

- Posting to external channels (Slack, email, mobile push). The
  digest is rendered in the chat response only.
- Cross-topic deduplication. Each topic has its own history file.
- Windows longer than 24 hours. Invoke once per morning.
- Topics that require pulling data from another skill (e.g. Spotify
  followed-artists news). Those belong in separate skills that can
  delegate to `spotify-sheets`.
