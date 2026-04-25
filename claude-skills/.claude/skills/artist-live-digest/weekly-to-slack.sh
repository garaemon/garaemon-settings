#!/usr/bin/env bash
# Run the artist-live-digest skill and post the result to Slack.
# Intended to be invoked from a systemd --user timer as the Friday-morning job.
#
# A single `claude -p` invocation chains spotify-sheets, web search, and
# slack-post in one model session. Skip the Slack post entirely when the
# digest reports no new events.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "error: claude CLI not found or not executable at $CLAUDE_BIN" >&2
  exit 1
fi

cd "$PROJECT_DIR"

# Minimal allowlist. artist-live-digest needs the spotify-sheets run.sh
# (followed-artist list) and web search/fetch. The wrapper additionally
# allows the slack-post run.sh so the model can post the rendered digest.
# History reads/writes are scoped to the cache glob.
SPOTIFY_RUN_SH="${PROJECT_DIR}/.claude/skills/spotify-sheets/run.sh"
SLACK_RUN_SH="${PROJECT_DIR}/.claude/skills/slack-post/run.sh"
# The literal `~` is passed through to claude, which expands it per
# gitignore-style permission pattern semantics. Do not let the shell expand it.
# shellcheck disable=SC2088
HISTORY_GLOB='~/.cache/claude-private-skills/**'
allowed_tools=(
  WebSearch
  WebFetch
  "Read(/**)"
  "Read(${HISTORY_GLOB})"
  "Write(${HISTORY_GLOB})"
  "Edit(${HISTORY_GLOB})"
  "Bash(date:*)"
  "Bash(mkdir:*)"
  "Bash(${SPOTIFY_RUN_SH}:*)"
  "Bash(${SLACK_RUN_SH}:*)"
)

echo "=== $(date -Is) artist-live-digest ==="
prompt="Run the artist-live-digest skill. "
prompt+="If at least one new event remains after dedup, post the rendered "
prompt+="Japanese digest body to Slack via the slack-post skill with the "
prompt+="--markdown flag. If there are zero new events, do not post anything "
prompt+="to Slack and exit."

exec "$CLAUDE_BIN" -p "$prompt" --allowedTools "${allowed_tools[@]}"
