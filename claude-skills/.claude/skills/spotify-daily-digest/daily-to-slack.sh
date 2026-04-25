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

# Load env vars from the repo-root .env if present. systemd --user does not
# inherit the interactive shell environment, so SPOTIFY_SPREADSHEET_ID and
# friends would otherwise be unset when the timer fires. `set -a` auto-exports
# every assignment, so both `KEY=value` and `export KEY=value` lines work.
ENV_FILE="$PROJECT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# Minimal allowlist. spotify-daily-digest delegates retrieval to spotify-sheets
# and slack-post via their dockerized run.sh at fixed paths. The Write/Read
# scope on /tmp lets the model stage the digest body in /tmp/spotify-daily-
# digest-body.md and pass it via slack-post --text-file, which avoids the
# Bash arg validator rejecting long markdown bodies inlined into --text.
SPOTIFY_RUN_SH="${PROJECT_DIR}/.claude/skills/spotify-sheets/run.sh"
SLACK_RUN_SH="${PROJECT_DIR}/.claude/skills/slack-post/run.sh"
allowed_tools=(
  WebSearch
  WebFetch
  "Bash(date:*)"
  "Bash(${SPOTIFY_RUN_SH}:*)"
  "Bash(${SLACK_RUN_SH}:*)"
  "Read(/tmp/**)"
  "Write(/tmp/**)"
  "Edit(/tmp/**)"
)

echo "=== $(date -Is) spotify-daily-digest ==="
prompt="Run the spotify-daily-digest skill for the last 24 hours. "
prompt+="If at least one song was liked in that window, post the rendered Japanese "
prompt+="digest body to Slack via the slack-post skill with the --markdown flag. "
prompt+="Stage the body in a file under /tmp (e.g. /tmp/spotify-daily-digest-body.md) "
prompt+="and pass it via 'slack-post post --text-file <path> --markdown' rather than "
prompt+="inlining the body into --text; this avoids Bash argument validator rejections "
prompt+="on multi-line markdown headings. "
prompt+="If zero songs were liked (the spotify-sheets new-since output reports 0 "
prompt+="songs), do not post anything to Slack and exit cleanly."

exec "$CLAUDE_BIN" -p "$prompt" --allowedTools "${allowed_tools[@]}"
