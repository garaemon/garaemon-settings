# claude-private-skills

This is my private set of Claude Code skills.

The repository is the single source of truth for my skills: `~/.claude/skills`
is a symlink to `.claude/skills` here, so every skill is available globally and
edits are live (no copy/sync step). See [Installation](#installation) below.

## Skills

### Remote-control & automation

These skills are designed and implemented with the intent of being used from the
Claude app on smartphones or desktop via Claude Code's `/remote-control`.

- [add-paper-from-url](.claude/skills/add-paper-from-url/SKILL.md) — Add a paper to Paperpile from a PDF URL and attach a Japanese Ochiai-format summary as a note via the [`paperpile`](https://github.com/garaemon/paperpile) CLI.
- [spotify-sheets](.claude/skills/spotify-sheets/SKILL.md) — Search and browse the user's Spotify library (liked songs, followed artists) exported to Google Sheets. Runs in a hardened Docker container with a read-only service-account key mount.
- [spotify-daily-digest](.claude/skills/spotify-daily-digest/SKILL.md) — Produce a morning digest of the songs liked in the last 24 hours, enriched with web-searched background for each track and artist.
- [slack-post](.claude/skills/slack-post/SKILL.md) — Post a message to a Slack channel (or DM) via the Slack Web API. Runs in a hardened Docker container with the bot token mounted read-only; designed for scheduled jobs like a daily morning digest.
- [news-digest](.claude/skills/news-digest/SKILL.md) — Produce a morning news digest for a configured topic (AI, software, NBA, …) with web-searched headlines, category grouping, and cross-day deduplication against a persistent history file. Topics are markdown configs under `topics/`, so adding a new topic requires no code change.
- [pdf2zh](.claude/skills/pdf2zh/SKILL.md) — Translate a PDF to Japanese via the `pdf2zh` (PDFMathTranslate) CLI using Gemini. Runs in a hardened Docker container with a read-only Gemini API key file mount.
- [artist-live-digest](.claude/skills/artist-live-digest/SKILL.md) — Produce a Japanese digest of upcoming live concerts in a configured city (default: Los Angeles) for the user's followed Spotify artists. Delegates the artist list to `spotify-sheets`, enriches via web search within a configurable day window, and dedupes against a persistent history file. Ships a Friday-morning systemd timer that posts via `slack-post`.
- [morning-brief](.claude/skills/morning-brief/SKILL.md) — Produce a Japanese morning brief of today's Google Calendar events (across all calendars), today's unread inbox mail, and the GitHub items needing attention (review requests, recent own PRs, recently-active assigned issues), triaged and rendered directly in the chat so the user engages with it rather than receiving a hands-off digest. Reads Calendar and Gmail via the `gws-secure` wrapper and GitHub via `gh search`; Slack posting is opt-in.
- [daily-wrapup](.claude/skills/daily-wrapup/SKILL.md) — Wrap up the user's day (the end-of-day counterpart to `morning-brief`): write a Japanese summary of the user's GitHub activity for a day (pull requests and issues they touched, commits they authored, grouped by repository) plus the day's events from their own (primary) Google Calendar into their org-roam daily note as a Claude-generated, unreviewed subtree, then commit and push the org repo after the user confirms, and open the note in Emacs when a server is reachable. Reads GitHub with `gh search` and the calendar through the `gws-secure` wrapper.

### Local development workflow

These are general-purpose coding-workflow skills (no network or credentials of
their own beyond `gh`/`git`), used in any repository.

- [code-review](.claude/skills/code-review/SKILL.md) — Review changes on the current branch against the auto-detected default branch, producing a structured `REVIEW.md` and posting inline review comments on specific file lines via the GitHub API.
- [code-review-loop](.claude/skills/code-review-loop/SKILL.md) — Iterative review-and-fix loop: run the `code-review` skill via a subagent, fix every reported issue, then re-review until no findings remain (up to 5 iterations).
- [create-pr](.claude/skills/create-pr/SKILL.md) — Automate the full pull-request workflow: stage changes, commit, push, and open a GitHub PR.
- [fix-agent-todo](.claude/skills/fix-agent-todo/SKILL.md) — Find every `TODO(agent)` marker in the codebase, implement the change each one describes, and remove the comment afterward. Other TODO variants are left untouched.
- [improve-english](.claude/skills/improve-english/SKILL.md) — Improve English in changes bound for a PR: fix spelling in identifiers, smooth comment grammar, and translate Japanese comments into English, scoped to the diff against `origin/main`.

## Installation

`~/.claude/skills` is a symlink to this repository's `.claude/skills`, so all
skills are available in every directory and editing a skill here takes effect
immediately. On a new machine, clone the repository and point `~/.claude/skills`
at it:

```bash
git clone <this-repo> ~/ghq/github.com/garaemon/claude-private-skills
ln -s ~/ghq/github.com/garaemon/claude-private-skills/.claude/skills ~/.claude/skills
```

Machine configuration (the thin `~/.claude/CLAUDE.md`, etc.) is managed
separately by chezmoi; the skills directory is deliberately left out of chezmoi
(`.claude/skills` is in its `.chezmoiignore`) so this repository is the only
owner of skill files.

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
