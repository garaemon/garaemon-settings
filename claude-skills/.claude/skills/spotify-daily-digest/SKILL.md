---
name: spotify-daily-digest
description: |
  Produce a morning digest of Spotify songs the user liked in the last 24 hours,
  enriched with web-searched background for each track and artist. Delegates
  retrieval to the spotify-sheets skill and uses web search for enrichment.
  Trigger when the user asks for a daily or morning summary of their liked songs,
  or says things like "今朝の好きになった曲", "昨日ライクした曲まとめて",
  "daily liked songs digest", "morning music summary", "this morning's likes".
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh:*), Bash(date:*), WebSearch, WebFetch
---

# Spotify Daily Digest Skill

Pull the songs the user liked in the last 24 hours from their Spotify-Sheets
library and present a background-rich morning summary: who made each song,
when it was released, what the artist is known for, and any notable context.

The user likes songs independently of artists — they may not recognise the
performer — so each entry must introduce the artist as if for the first time.

## Prerequisites

- The `spotify-sheets` skill is installed and its Docker image is built.
  If `run.sh` fails because the image is missing, surface the build hint
  it prints and stop.
- `SPOTIFY_SPREADSHEET_ID` is exported and the service account key lives
  at `~/.config/spotify-sheets/sa.json` (see the spotify-sheets skill for
  full setup).
- Network access is available for web searches.

## Workflow

### Step 1: Compute the 24-hour window

Resolve yesterday's date in `YYYY-MM-DD` from the current system time. The
sheet only stores per-day `Added At` values, so a 24-hour window is
approximated by "since yesterday".

```bash
SINCE=$(date -d yesterday +%Y-%m-%d)
```

On macOS (BSD `date`): `SINCE=$(date -v-1d +%Y-%m-%d)`. Prefer the live
`date` call over the today's-date value seen in context so the window stays
correct across sessions that span midnight.

### Step 2: Fetch newly liked songs

Delegate to the spotify-sheets skill:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh" new-since "$SINCE"
```

Output format per song:

```text
N.
  <Track Name> - <Artists>
  Album: <Album Name>
  Genres: <Genres>
  Released: <Release Date>  Added: <YYYY-MM-DD>
  <Track Link>
```

Followed by a line `Unique artists in new likes: <comma-separated list>`.

If the output says `Songs liked since <date> (0):`, stop and report that
nothing was liked in the last 24 hours. Do NOT widen the window silently or
fabricate entries.

### Step 3: Enrich each artist via web search

This step is mandatory. For every unique artist in the result, run one
`WebSearch` with a query such as:

```text
<Artist Name> musician background genre origin
```

From the top results, extract:

- Origin / nationality / active years
- Primary genre(s) and sound description
- Notable works, collaborations, or labels
- Context relevant to the liked track (recent single, soundtrack placement,
  cover, tribute, etc.)

If the artist name is ambiguous (common word, multiple artists share it),
refine the query with the liked song title or the genres already listed on
the sheet row. When a search returns no reliable result, mark that artist
as "情報が見つかりませんでした" in the digest rather than fabricating.

### Step 4: Enrich each song when relevant

For tracks with clearly notable song-level context (chart single, cover,
theme song, collaboration), run a second, lightweight search:

```text
"<Track Name>" <Artist Name> song background release
```

One search per track is enough. Skip when Step 3 already covered the song's
story.

### Step 5: Suggest follows

For each unique artist in the list, check whether the user already follows
them:

```bash
"$CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh" artist-detail "<name>"
```

If the command returns matched songs but zero matching entries under the
"Artists matching" heading, the user likes the artist's songs but has not
yet followed them — a good candidate to highlight at the end of the digest.

### Step 6: Render the morning digest in Japanese

Compose the digest as a Japanese chat response. Structure:

1. One-sentence headline with the count and window, e.g.
   "昨日から今朝までに N 曲をライクしました（YYYY-MM-DD 以降）。"
2. Per-track section, in the order returned by `new-since`:
   - Track title, artist, and Spotify link
   - Album, release year, genres
   - 2–4 Japanese sentences covering: who the artist is, why this song is
     notable, and any connection to genres the user already listens to.
3. Closing "今日のおすすめフォロー" line: recommend 1–2 artists from
   Step 5 that the user has liked but not followed, one sentence each. If
   every artist is already followed, omit this section.

Ground every factual claim in a web-search result. If the searches were
inconclusive for a given track, say so in Japanese rather than guessing.

## Output rules

- The chat response is in Japanese; this SKILL.md and any files written stay
  in English.
- Only describe songs that actually appeared in the `new-since` output.
- Only recommend follows among artists that appeared in the 24-hour window.
- Keep each per-track blurb to roughly four sentences — the user reads this
  at breakfast.

## Error handling

- `run.sh` prints a build hint and exits non-zero: surface the hint to the
  user verbatim, do not attempt to build.
- `SPOTIFY_SPREADSHEET_ID` unset or key file rejected: surface the error; do
  not retry.
- Web search rate-limited or empty for one artist: note it in the digest
  under the affected entry and continue with the rest.

## Out of scope

- Modifying the Spotify library or the spreadsheet.
- Digests for windows longer than 24 hours (invoke spotify-sheets
  `new-since` directly for that).
- Posting the digest to external channels (Slack, email, etc.).
