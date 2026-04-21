# systemd --user units for the morning news digest

These unit files drive `daily-digest-to-slack.sh`, the wrapper that runs the
`news-digest` skill for each configured topic and posts the result to Slack
via the `slack-post` skill.

## Files

- `news-digest-slack.service` — oneshot service that invokes the wrapper
  script. `%h` in the unit resolves to the user's home directory, so the
  same file works on any machine where the repo is cloned at
  `~/ghq/github.com/garaemon/claude-private-skills`.
- `news-digest-slack.timer` — fires the service every day at 08:00 local
  time with a small randomized delay. `Persistent=true` makes the timer
  catch up once after a missed run (e.g. laptop asleep at 08:00).

## Install

```bash
mkdir -p ~/.config/systemd/user
cp news-digest-slack.service ~/.config/systemd/user/
cp news-digest-slack.timer   ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now news-digest-slack.timer
```

## Inspect

```bash
systemctl --user list-timers news-digest-slack.timer
systemctl --user status news-digest-slack.timer
journalctl --user -u news-digest-slack.service -n 200 --no-pager
```

## Run once on demand

```bash
systemctl --user start news-digest-slack.service
```

## Remove

```bash
systemctl --user disable --now news-digest-slack.timer
rm ~/.config/systemd/user/news-digest-slack.service \
   ~/.config/systemd/user/news-digest-slack.timer
systemctl --user daemon-reload
```
