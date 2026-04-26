# claude-private-skills

This is my private set of Claude Code skills.
These skills are designed and implemented with the intent of being used from the Claude app on
smartphones or desktop via Claude Code's `/remote-control`.

## Skills

- [add-paper-from-url](.claude/skills/add-paper-from-url/SKILL.md) — Add a paper to Paperpile from a PDF URL and attach a Japanese Ochiai-format summary as a note via the [`paperpile`](https://github.com/garaemon/paperpile) CLI.
- [spotify-sheets](.claude/skills/spotify-sheets/SKILL.md) — Search and browse the user's Spotify library (liked songs, followed artists) exported to Google Sheets. Runs in a hardened Docker container with a read-only service-account key mount.
- [spotify-daily-digest](.claude/skills/spotify-daily-digest/SKILL.md) — Produce a morning digest of the songs liked in the last 24 hours, enriched with web-searched background for each track and artist.
- [org-graduate](.claude/skills/org-graduate/SKILL.md) — Scan recent org-roam daily notes and produce a graduation proposal (dry-run) that surfaces which daily entries should seed new org-roam nodes and which should be appended as log entries to existing nodes.
- [slack-post](.claude/skills/slack-post/SKILL.md) — Post a message to a Slack channel (or DM) via the Slack Web API. Runs in a hardened Docker container with the bot token mounted read-only; designed for scheduled jobs like a daily morning digest.
- [news-digest](.claude/skills/news-digest/SKILL.md) — Produce a morning news digest for a configured topic (AI, software, NBA, …) with web-searched headlines, category grouping, and cross-day deduplication against a persistent history file. Topics are markdown configs under `topics/`, so adding a new topic requires no code change.
- [org-deepsearch](.claude/skills/org-deepsearch/SKILL.md) — Research a user-specified topic via web search and related-paper lookup, draft a source-cited Japanese org-roam node, and open a PR against the configured org repository (dry-run first, apply mode opt-in).
- [pdf2zh](.claude/skills/pdf2zh/SKILL.md) — Translate a PDF to Japanese via the `pdf2zh` (PDFMathTranslate) CLI using Gemini. Runs in a hardened Docker container with a read-only Gemini API key file mount.
- [artist-live-digest](.claude/skills/artist-live-digest/SKILL.md) — Produce a Japanese digest of upcoming live concerts in a configured city (default: Los Angeles) for the user's followed Spotify artists. Delegates the artist list to `spotify-sheets`, enriches via web search within a configurable day window, and dedupes against a persistent history file. Ships a Friday-morning systemd timer that posts via `slack-post`.
