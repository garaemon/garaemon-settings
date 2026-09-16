---
name: spotify-sheets
description: |
  Search and browse the user's Spotify library (liked songs, followed artists) exported
  to Google Sheets. Supports daily digests of new likes, artist-detail lookup, genre
  statistics, and full-text search. The CLI runs inside a hardened Docker container
  with a read-only service account key mount.
  Trigger when the user asks about their Spotify library, liked songs, or followed
  artists, or says things like "spotifyのライクした曲", "最近好きになった曲",
  "フォローしてるアーティスト", "show my liked songs", "search spotify library",
  "今日の新しい好きな曲".
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/spotify-sheets/run.sh:*)
---

# Spotify Sheets Skill

Search and browse the user's Spotify library stored in Google Sheets. The CLI runs
inside a hardened Docker container so it cannot touch the host filesystem beyond a
read-only mount of the service account key.

## Prerequisites

- Docker is installed and the daemon is running.
- A Google Sheets spreadsheet with two sheets:
  - `Spotify Liked Songs` with columns: `Track Name`, `Artists`, `Album Name`, `Genres`, `Release Date`, `Added At`, `Track Link`
  - `Spotify Followed Artists` with columns: `Artist Name`, `Genres`, `Spotify URL`
- A Google service account JSON key with read access to the spreadsheet.

## One-time setup

1. Place the service account JSON at the default location and tighten permissions:

   ```bash
   mkdir -p ~/.config/spotify-sheets
   cp /path/to/sa.json ~/.config/spotify-sheets/sa.json
   chmod 600 ~/.config/spotify-sheets/sa.json
   ```

   To use a different path, export `GOOGLE_SA_KEY_FILE` pointing at the JSON file.

2. Export the spreadsheet ID (typically in your shell profile):

   ```bash
   export SPOTIFY_SPREADSHEET_ID=<your-spreadsheet-id>
   ```

3. Build the Docker image once:

   ```bash
   docker build -t spotify-sheets:local \
     "$CLAUDE_PLUGIN_ROOT/skills/spotify-sheets"
   ```

   Rebuild after updating the skill to pick up script changes.

## Commands

Invoke via `run.sh`; arguments are passed through to the in-container CLI.

| Command | Description |
| --- | --- |
| `list-songs [--limit N]` | List recent liked songs (default N=20) |
| `list-artists` | List all followed artists |
| `search [--songs / --artists] <query>` | Full-text search across title, artist, album, genre |
| `new-since <YYYY-MM-DD>` | Songs liked since a date, with unique artist summary |
| `artist-detail <name>` | Show artist profile and all their liked songs |
| `genres` | Genre frequency across songs and artists |
| `stats` | Library totals, date range, top 10 genres |

## Example invocations

```bash
run.sh list-songs --limit 50
run.sh search "math rock"
run.sh new-since 2026-04-17
run.sh artist-detail "NABOWA"
```

## Isolation guarantees

Each `run.sh` invocation starts a container with:

- `--read-only` root filesystem, writable `/tmp` tmpfs only
- `--cap-drop ALL` and `--security-opt no-new-privileges`
- `--memory 256m --cpus 0.5` resource limits
- Non-root `node` user inside the container
- Service account key mounted read-only at `/secrets/sa.json`
- `--network bridge` (outbound only; required to reach Google Sheets API)

`run.sh` additionally guards against common misconfigurations before launching:

- Refuses to run if the Docker image is missing and prints the build command
- Rejects the key file if it is a symlink or not a regular file
- Requires mode `600` or `400` on the key file
- Fails fast if `SPOTIFY_SPREADSHEET_ID` is unset

## When to use

- The user asks about their Spotify library, liked songs, or followed artists
- The user wants to search for a song or artist in their collection
- The user asks about genres or music taste
- The user wants a link to a song or artist on Spotify

## Scheduled task patterns

### Daily new-likes digest

Use `new-since` with yesterday's date to find newly liked songs and summarise the
new artists:

```bash
run.sh new-since "$(date -d yesterday +%Y-%m-%d)"
```

### Artist live event lookup

Use `list-artists` or `artist-detail` to get artist names, then use a web search
tool to find upcoming concerts.

## Out of scope

This skill only reads the library. It does NOT:

- Write to the spreadsheet
- Call the Spotify Web API directly (refreshing the sheet is handled elsewhere)
- Manage playlists
