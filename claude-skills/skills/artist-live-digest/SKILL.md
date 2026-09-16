---
name: artist-live-digest
description: |
  Produce a Japanese digest of upcoming live concerts in a configured city
  (default: Los Angeles) for the user's followed Spotify artists. Delegates
  the artist list to the spotify-sheets skill and uses web search to find
  tour dates within the next 60 days. Supports cross-run deduplication
  against a persistent history file so already-reported events are not
  repeated.
  Trigger when the user asks about upcoming concerts for the artists they
  follow, or says things like "フォローしてるアーティストのライブ",
  "LAでライブある？", "今度のライブまとめて", "upcoming concerts for my
  followed artists", "artist live digest", "近場のライブ教えて".
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh:*), Bash(date:*), Bash(mkdir:*), WebSearch, WebFetch
---

# Artist Live Digest Skill

Surface upcoming live shows in a configured metro area (default: Los
Angeles) for the artists the user follows on Spotify. The skill pulls the
followed-artist list from `spotify-sheets`, runs one web search per artist
for tour dates, filters to events within the configured city and time
window, and produces a Japanese digest grouped by artist.

The skill is read-only and does not post anywhere. The `weekly-to-slack.sh`
wrapper drives the Friday-morning Slack post.

## Scope: followed artists only (intentional)

The first iteration only covers artists in the `Spotify Followed Artists`
sheet, not artists derived from the user's liked songs. This is a deliberate
trade-off:

- The followed-artist list is curated by the user and small enough (tens of
  names) to web-search exhaustively in one run.
- The liked-song artist list is hundreds of names. Searching every one of
  them every week would be wasteful and noisy, and would exceed reasonable
  search budgets.

Do not silently widen the scope. If the user asks for liked-song artists as
well, that is a separate iteration with its own filtering strategy
(e.g. only artists with N+ liked songs, or only those liked recently).

## Prerequisites

- The `spotify-sheets` skill is installed and its Docker image is built.
  If `run.sh` fails because the image is missing, surface the build hint
  it prints and stop.
- `SPOTIFY_SPREADSHEET_ID` is exported and the service-account key lives
  at `~/.config/spotify-sheets/sa.json` (see the spotify-sheets skill for
  full setup).
- Network access is available for web searches.
- A writable history directory. Defaults to
  `~/.cache/claude-private-skills/artist-live-history/`. The skill will
  create it on first run.

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `ARTIST_LIVE_CITY` | `Los Angeles` | Metro area to filter events to. Used both in the search query and in the post-search filter. |
| `ARTIST_LIVE_WINDOW_DAYS` | `60` | Number of days from today to include. Events outside this window are dropped. |
| `ARTIST_LIVE_HISTORY_FILE` | `~/.cache/claude-private-skills/artist-live-history/la.tsv` | Tab-separated dedup history. Override per-city when running multiple cities. |

## Workflow

### Step 1: Resolve today's date and config

```bash
TODAY=$(date +%Y-%m-%d)
CITY="${ARTIST_LIVE_CITY:-Los Angeles}"
WINDOW_DAYS="${ARTIST_LIVE_WINDOW_DAYS:-60}"
HISTORY_FILE="${ARTIST_LIVE_HISTORY_FILE:-$HOME/.cache/claude-private-skills/artist-live-history/la.tsv}"
mkdir -p "$(dirname "$HISTORY_FILE")"
```

Compute the window end as `TODAY + WINDOW_DAYS`. On Linux use
`date -d "+${WINDOW_DAYS} days" +%Y-%m-%d`; on macOS use
`date -v+${WINDOW_DAYS}d +%Y-%m-%d`. Prefer the live `date` call over
any cached today's-date in the model context so the window stays correct
across sessions that span midnight.

### Step 2: Pull the followed-artist list

Delegate to spotify-sheets:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh" list-artists
```

The command prints one line per followed artist with the name, genres, and
Spotify URL. Parse the artist names from the output. If the list is empty,
stop and report a Japanese message indicating no followed artists were
found. Do NOT fall back to liked-song artists.

### Step 3: Load the dedup history

If `HISTORY_FILE` exists, read it. Each line is tab-separated:

```text
YYYY-MM-DD<TAB><Artist><TAB><EventURL>
```

Collect the set of `(Artist, EventURL)` pairs and the set of EventURLs.
Treat a hit on either as "already delivered". If the file does not exist,
treat the set as empty.

### Step 4: Search for tour dates in parallel batches

For each followed artist, run exactly one `WebSearch` with a query like:

```text
<Artist> <CITY> concert <YEAR> tour dates
```

where `<YEAR>` is the year portion of `TODAY`.

Issue these searches in **parallel batches of 8–10**: emit 8–10
`WebSearch` tool calls in a single response, wait for all of them to
come back, then move on to the next batch. The Claude Code tool layer
handles parallel `WebSearch` fine, and sequential one-at-a-time runs
make a typical followed-artist list take many minutes. Per-artist
attribution is still trivial because the artist name is in each
query. If a single search in a batch errors out, log it and continue
with the rest of the batch — partial failures should not stop the run.

Across batches the per-artist budget is still exactly one query, and
the per-event filtering rules below apply unchanged.

If the snippet clearly indicates no upcoming dates (e.g. "no upcoming
shows"), skip to the next artist. If the snippet is ambiguous about the
date or city, fetch the page with `WebFetch` to disambiguate. Discard
results whose:

- City is not the configured `CITY` or a clearly nearby venue (e.g. for
  `Los Angeles`: Inglewood, Anaheim, Long Beach, Pasadena are fine;
  San Diego is not).
- Date is in the past or further than `WINDOW_DAYS` from `TODAY`.
- Source is a generic aggregator landing page with no specific event URL.

Never fabricate. If no real event can be grounded for an artist, drop
that artist silently from the digest.

### Step 5: Dedupe against history

Drop events whose URL or `(Artist, URL)` pair already appears in the
history set from Step 3. Normalise URLs minimally (strip `utm_*` and
`#fragment`) before comparing.

If zero events remain after dedup, stop and respond with a single
Japanese line saying there are no new live events for today, including
the date, the city, and the window length. Do not update the history
file in this case.

### Step 6: Render the Japanese digest

Group events by artist (alphabetical by artist name). For each artist,
list each event with date, venue, and ticket / source link. Two to four
Japanese sentences per event maximum.

Suggested structure:

- Header line with a music emoji, the date, the city, and the window.
- One bold heading per artist who has surviving events.
- One bullet per event: date, venue, and a markdown link to the source.
- Two to four Japanese sentences per event covering ticket-sale status,
  co-headliners, tour name, etc., grounded in the search result.

Skip the artist heading if no events survived for them.

### Step 7: Append to the history file

Append one line per delivered event in the format from Step 3
(`YYYY-MM-DD<TAB>Artist<TAB>EventURL`). After appending, if the file
exceeds 200 lines, truncate to the most recent 200 lines (`tail -n 200`).

If Step 5 produced zero events, skip this step entirely.

## Output rules

- Chat response is in Japanese; this SKILL.md, history files, and any
  other written files stay in English / ASCII identifiers.
- Only report events grounded in a real web search result with a real URL.
- Only one city per invocation. Run the skill again with a different
  `ARTIST_LIVE_CITY` and `ARTIST_LIVE_HISTORY_FILE` for additional cities.

## Error handling

- `spotify-sheets` Docker image missing: surface the build hint from
  `run.sh` verbatim and stop. Do not attempt to build.
- `SPOTIFY_SPREADSHEET_ID` unset or service-account key rejected: surface
  the underlying error and stop.
- Empty followed-artist list: emit the Japanese "no followed artists"
  message and stop. Do not fall back to liked-song artists.
- Web search rate-limited or empty for a single artist: skip that artist
  and continue with the rest. Note in the digest if a meaningful number
  were skipped.
- History directory not writable: surface the path and the error; do
  not silently skip the append step.

## Out of scope

- Posting the digest to Slack, email, or any other channel — that is
  the job of `weekly-to-slack.sh`.
- Writing back to the Google Sheet (the `spotify-sheets` skill is
  read-only by design).
- Buying tickets, holding tickets, or interacting with ticketing APIs.
- Liked-song-derived artists (see "Scope" above).
- Multi-city runs in a single invocation. Invoke once per city.
- Windows longer than `ARTIST_LIVE_WINDOW_DAYS`. Adjust the env var
  rather than overriding inline.
