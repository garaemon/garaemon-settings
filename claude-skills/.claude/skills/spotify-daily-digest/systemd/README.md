# systemd --user units for the morning Spotify likes digest

These unit files drive `daily-to-slack.sh`, the wrapper that runs the
`spotify-daily-digest` skill once and posts the resulting Japanese digest to
Slack via the `slack-post` skill. When zero songs were liked in the window,
the wrapper instructs the model to skip the Slack post entirely.

## Files

- `spotify-daily-digest-slack.service` — oneshot service that invokes the
  wrapper script. `%h` in the unit resolves to the user's home directory, so
  the same file works on any machine where the repo is cloned at
  `~/ghq/github.com/garaemon/claude-private-skills`.
- `spotify-daily-digest-slack.timer` — fires the service every day at 07:30
  local time with a small randomized delay. `Persistent=true` makes the
  timer catch up once after a missed run (e.g. laptop asleep at 07:30).
  07:30 is staggered ahead of the 08:00 news-digest timer so the two
  morning jobs do not contend for resources.

## Prerequisites

- The `spotify-sheets` Docker image is built and `SPOTIFY_SPREADSHEET_ID`
  is reachable by the wrapper. systemd `--user` services do NOT inherit
  the interactive shell environment, so `daily-to-slack.sh` sources the
  repo-root `.env` (if present) at startup. Put `SPOTIFY_SPREADSHEET_ID`
  there in either `KEY=value` or `export KEY=value` form. The service
  account key lives at `~/.config/spotify-sheets/sa.json` (or wherever
  `GOOGLE_SA_KEY_FILE` points).
- The `slack-post` Docker image is built and the bot token config lives
  at `~/.config/slack-post/config.json` (or wherever `SLACK_CONFIG_FILE`
  points). `default_channel` should be set in that config so the wrapper
  does not need to pass `--channel`.
- The `claude` CLI is installed at `~/.local/bin/claude` (override with
  `CLAUDE_BIN` in the environment if installed elsewhere).

## Install

```bash
mkdir -p ~/.config/systemd/user
cp spotify-daily-digest-slack.service ~/.config/systemd/user/
cp spotify-daily-digest-slack.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now spotify-daily-digest-slack.timer
```

## Inspect

```bash
systemctl --user list-timers spotify-daily-digest-slack.timer
systemctl --user status spotify-daily-digest-slack.timer
journalctl --user -u spotify-daily-digest-slack.service -n 200 --no-pager
```

## Run once on demand

```bash
systemctl --user start spotify-daily-digest-slack.service
```

## Remove

```bash
systemctl --user disable --now spotify-daily-digest-slack.timer
rm ~/.config/systemd/user/spotify-daily-digest-slack.service \
   ~/.config/systemd/user/spotify-daily-digest-slack.timer
systemctl --user daemon-reload
```
