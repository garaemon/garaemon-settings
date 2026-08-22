# systemd --user units for the weekly artist-live-digest

These unit files drive `weekly-to-slack.sh`, the wrapper that runs the
`artist-live-digest` skill and posts the result to Slack via the
`slack-post` skill.

## Files

- `artist-live-digest-slack.service` — oneshot service that invokes the
  wrapper script. `%h` in the unit resolves to the user's home directory,
  so the same file works on any machine where the repo is cloned at
  `~/ghq/github.com/garaemon/claude-private-skills`.
- `artist-live-digest-slack.timer` — fires the service every Friday at
  07:00 local time with a small randomized delay. `Persistent=true` makes
  the timer catch up once after a missed run (e.g. laptop asleep at
  07:00 on a Friday).

## Prerequisites

- The `spotify-sheets` skill is installed and its Docker image
  (`spotify-sheets:local`) is built; `SPOTIFY_SPREADSHEET_ID` is reachable
  by the wrapper. systemd `--user` services do NOT inherit the
  interactive shell environment, so `weekly-to-slack.sh` sources the
  repo-root `.env` (if present) at startup. Put `SPOTIFY_SPREADSHEET_ID`
  there in either `KEY=value` or `export KEY=value` form. The
  service-account key for spotify-sheets is in place per that skill's
  README.
- The `slack-post` skill is installed and its Docker image
  (`slack-post:local`) is built; the bot config file is in place per
  that skill's README.
- The `claude` CLI is installed at `~/.local/bin/claude` (override via
  `CLAUDE_BIN` if it lives elsewhere).

## Environment variables

The wrapper itself reads the following (forwarded to the skill):

- `ARTIST_LIVE_CITY` — defaults to `Los Angeles`.
- `ARTIST_LIVE_WINDOW_DAYS` — defaults to `60`.
- `ARTIST_LIVE_HISTORY_FILE` — defaults to
  `~/.cache/claude-private-skills/artist-live-history/la.tsv`.

To set them for the systemd job, drop a `~/.config/environment.d/`
file (`systemd --user` reads them) or add `Environment=` lines to the
service unit.

## Install

```bash
mkdir -p ~/.config/systemd/user
cp artist-live-digest-slack.service ~/.config/systemd/user/
cp artist-live-digest-slack.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now artist-live-digest-slack.timer
```

## Inspect

```bash
systemctl --user list-timers artist-live-digest-slack.timer
systemctl --user status artist-live-digest-slack.timer
journalctl --user -u artist-live-digest-slack.service -n 200 --no-pager
```

## Run once on demand

```bash
systemctl --user start artist-live-digest-slack.service
```

## Remove

```bash
systemctl --user disable --now artist-live-digest-slack.timer
rm ~/.config/systemd/user/artist-live-digest-slack.service \
   ~/.config/systemd/user/artist-live-digest-slack.timer
systemctl --user daemon-reload
```
