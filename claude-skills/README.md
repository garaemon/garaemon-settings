# claude-private-skills

This is my private set of Claude Code skills.
These skills are designed and implemented with the intent of being used from the Claude app on
smartphones or desktop via Claude Code's `/remote-control`.

## Skills

- [add-paper-from-url](.claude/skills/add-paper-from-url/SKILL.md) — Add a paper to Paperpile from a PDF URL and attach a Japanese Ochiai-format summary as a note via the [`paperpile`](https://github.com/garaemon/paperpile) CLI.
- [spotify-sheets](.claude/skills/spotify-sheets/SKILL.md) — Search and browse the user's Spotify library (liked songs, followed artists) exported to Google Sheets. Runs in a hardened Docker container with a read-only service-account key mount.
- [spotify-daily-digest](.claude/skills/spotify-daily-digest/SKILL.md) — Produce a morning digest of the songs liked in the last 24 hours, enriched with web-searched background for each track and artist.
- [slack-post](.claude/skills/slack-post/SKILL.md) — Post a message to a Slack channel (or DM) via the Slack Web API. Runs in a hardened Docker container with the bot token mounted read-only; designed for scheduled jobs like a daily morning digest.
- [news-digest](.claude/skills/news-digest/SKILL.md) — Produce a morning news digest for a configured topic (AI, software, NBA, …) with web-searched headlines, category grouping, and cross-day deduplication against a persistent history file. Topics are markdown configs under `topics/`, so adding a new topic requires no code change.
- [pdf2zh](.claude/skills/pdf2zh/SKILL.md) — Translate a PDF to Japanese via the `pdf2zh` (PDFMathTranslate) CLI using Gemini. Runs in a hardened Docker container with a read-only Gemini API key file mount.
- [artist-live-digest](.claude/skills/artist-live-digest/SKILL.md) — Produce a Japanese digest of upcoming live concerts in a configured city (default: Los Angeles) for the user's followed Spotify artists. Delegates the artist list to `spotify-sheets`, enriches via web search within a configurable day window, and dedupes against a persistent history file. Ships a Friday-morning systemd timer that posts via `slack-post`.
- [morning-brief](.claude/skills/morning-brief/SKILL.md) — Produce a Japanese morning brief of today's Google Calendar events (across all calendars) and today's unread inbox mail, triaged and rendered directly in the chat so the user engages with it rather than receiving a hands-off digest. Reads Calendar and Gmail via the `gws-secure` wrapper; Slack posting is opt-in.
- [daily-digest](.claude/skills/daily-digest/SKILL.md) — Write a Japanese summary of the user's GitHub activity for a day (pull requests and issues they touched, commits they authored, grouped by repository) into their org-roam daily note as a Claude-generated, unreviewed subtree, then commit and push the org repo after the user confirms. Reads activity with `gh search`.

## Tools

### `gws-secure` — token-less Google Workspace CLI

`scripts/gws-secure` wraps the `gws` (Google Workspace CLI) so that **no OAuth
token is ever written to disk**. The OAuth client and refresh token live in
1Password; each call mints a short-lived access token in memory and passes it
to `gws` through `GOOGLE_WORKSPACE_CLI_TOKEN`, so `gws` persists no credential
(only the non-secret API discovery schema cache).

Unlike the Docker-backed skills above, `gws-secure` runs `gws` directly on the
host. This is a deliberate, documented exception to the repository's
Docker-isolation rule: the secret never reaches disk and `op` authentication is
host-bound, which provides isolation comparable to (and arguably stronger than)
a container. See `CLAUDE.md` for the rationale.

Setup:

1. Install the `gws` CLI and the other host prerequisites (`op`, `curl`,
   `jq`). `gws` ships as the `@googleworkspace/cli` npm package and must be
   on your `PATH`:

   ```bash
   npm install -g @googleworkspace/cli
   ```

2. Symlink the wrapper onto your `PATH` as `gws-secure`. Skills and
   automation call the bare `gws-secure` command (not the repo-relative
   `scripts/gws-secure` path), so this symlink is required, not optional:

   ```bash
   ln -s "$PWD/scripts/gws-secure" ~/.local/bin/gws-secure
   ```

3. Bootstrap once to mint a refresh token and store it in the 1Password
   item:

   ```bash
   gws-secure-bootstrap   # or: scripts/gws-secure-bootstrap
   ```

Usage — same arguments as `gws`:

```bash
gws-secure gmail users getProfile --params '{"userId":"me"}'
```

See [`scripts/README.md`](scripts/README.md) for prerequisites, configuration
variables, and details.
