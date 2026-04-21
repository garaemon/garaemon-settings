---
name: slack-post
description: |
  Post a message to a Slack channel (or DM) via the Slack Web API. The CLI
  runs inside a hardened Docker container with the bot token mounted
  read-only from a secret file on the host. Supports posting plain text,
  thread replies, and scheduled messages; designed to be invoked by other
  skills or cron-driven agents (e.g. a daily morning digest poster).
  Trigger when the user wants to send a Slack message from Claude Code, or
  says things like "slackに投稿して", "slackで知らせて", "slackに流して",
  "post to slack", "send slack message", "毎朝slackに投稿".
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/slack-post/run.sh:*)
---

# Slack Post Skill

Post a message to Slack via the Web API. The CLI runs inside a hardened
Docker container so it cannot touch the host filesystem beyond a read-only
mount of a single JSON config file that holds the bot token and an
optional default channel.

## Prerequisites

- Docker is installed and the daemon is running.
- A Slack bot token (starts with `xoxb-`) from a Slack App with the
  `chat:write` scope. If you need to post into a channel the bot is not yet
  a member of, invite the bot with `/invite @YourBot` in that channel.

## One-time setup

1. Create a JSON config file with the bot token and (optionally) a
   default channel, then tighten permissions:

   ```bash
   mkdir -p ~/.config/slack-post
   cat > ~/.config/slack-post/config.json <<'EOF'
   {
     "token": "xoxb-...",
     "default_channel": "#daily-digest"
   }
   EOF
   chmod 600 ~/.config/slack-post/config.json
   ```

   The `token` field is required. `default_channel` is optional; when
   set, `post` can be invoked without `--channel`. To use a different
   path, export `SLACK_CONFIG_FILE` pointing at the file.

2. Build the Docker image once:

   ```bash
   docker build -t slack-post:local \
     "$CLAUDE_PLUGIN_ROOT/skills/slack-post"
   ```

   Rebuild after updating the skill to pick up script changes.

## Commands

Invoke via `run.sh`; arguments are passed through to the in-container CLI.

| Command | Description |
| --- | --- |
| `post [--channel <id-or-name>] --text <text> [--thread <ts>]` | Post a message (optionally as a thread reply) |
| `post [--channel <id-or-name>] --stdin` | Read the message body from stdin |

`--channel` is optional when `default_channel` is set in the config file.
Explicit `--channel` always overrides the default. Channel accepts a
channel ID (`C0123456789`), a channel name (`#general`), or a user ID
for a DM (`U0123456789`). The `--thread` flag takes the parent message
timestamp (`ts`) returned by a previous post.

## Example invocations

```bash
run.sh post --text "Good morning!"                            # uses default_channel
run.sh post --channel "#announcements" --text "new release"   # override
run.sh post --channel "C0123456789" --text "build green" --thread "1712345678.001200"
printf 'line1\nline2\n' | run.sh post --stdin                 # uses default_channel
```

## Isolation guarantees

Each `run.sh` invocation starts a container with:

- `--read-only` root filesystem, writable `/tmp` tmpfs only
- `--cap-drop ALL` and `--security-opt no-new-privileges`
- `--memory 256m --cpus 0.5` resource limits
- Non-root `node` user inside the container
- Config file mounted read-only at `/secrets/config.json`
- `--network bridge` (outbound only; required to reach `slack.com`)

`run.sh` additionally guards against common misconfigurations before launching:

- Refuses to run if the Docker image is missing and prints the build command
- Rejects the config file if it is a symlink or not a regular file
- Requires mode `600` or `400` on the config file
- Passes stdin through only when `--stdin` is present among the arguments

## Scheduled task patterns

### Daily morning digest

Combine with another skill that produces the body (e.g.
`spotify-daily-digest`) and pipe the output in. With `default_channel`
set in the config file, the invocation stays short:

```bash
./produce-digest.sh | run.sh post --stdin
```

### Thread reply to a known message

```bash
run.sh post --channel "#alerts" \
  --thread "1712345678.001200" \
  --text "follow-up details"
```

## Out of scope

This skill is intentionally minimal. It does NOT:

- List channels, users, or message history
- Upload files or images
- Edit or delete previously posted messages
- Manage reactions or reminders

Extend the CLI or author a sibling skill if those features become needed.
