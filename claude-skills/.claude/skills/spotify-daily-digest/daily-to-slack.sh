#!/usr/bin/env bash
# Run the spotify-daily-digest skill once and post the result to Slack.
# Intended to be invoked from a systemd --user timer as the morning digest job.
#
# A single `claude -p` invocation chains spotify-daily-digest and slack-post.
# When zero songs were liked in the window, the prompt instructs the model to
# skip the Slack post and exit cleanly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "error: claude CLI not found or not executable at $CLAUDE_BIN" >&2
  exit 1
fi

cd "$PROJECT_DIR"

# Minimal allowlist. spotify-daily-digest delegates retrieval to spotify-sheets
# and writes nothing of its own, so no Read/Write globs are needed. slack-post
# is invoked through its dockerized run.sh at a fixed path.
SPOTIFY_RUN_SH="${PROJECT_DIR}/.claude/skills/spotify-sheets/run.sh"
SLACK_RUN_SH="${PROJECT_DIR}/.claude/skills/slack-post/run.sh"
allowed_tools=(
  WebSearch
  WebFetch
  "Bash(date:*)"
  "Bash(${SPOTIFY_RUN_SH}:*)"
  "Bash(${SLACK_RUN_SH}:*)"
)

echo "=== $(date -Is) spotify-daily-digest ==="
prompt="Run the spotify-daily-digest skill for the last 24 hours. "
prompt+="If at least one song was liked in that window, post the rendered Japanese "
prompt+="digest body to Slack via the slack-post skill with the --markdown flag. "
prompt+="If zero songs were liked (the spotify-sheets new-since output reports 0 "
prompt+="songs), do not post anything to Slack and exit cleanly."

exec "$CLAUDE_BIN" -p "$prompt" --allowedTools "${allowed_tools[@]}"
