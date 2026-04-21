#!/usr/bin/env bash
# Run the news-digest skill for each topic and post the result to Slack.
# Intended to be invoked from a systemd --user timer as the morning digest job.
#
# Each topic is processed by one `claude -p` invocation with a Japanese prompt
# that chains news-digest and slack-post. Topics run sequentially so a failure
# in one does not block the others.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"

if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo "error: claude CLI not found or not executable at $CLAUDE_BIN" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  topics=("$@")
else
  topics=(ai software nba)
fi

cd "$PROJECT_DIR"

# Minimal allowlist. news-digest only needs web search, path-scoped file IO
# (project tree for reads, history dir for reads/writes), and slack-post only
# needs to invoke its dockerized run.sh at a fixed path. Intentionally no
# broad Bash patterns: Read/Write/Edit fully cover the file IO the skill does,
# and the model carries today's date in its context, so `cat`/`echo`/`date`
# etc. are unnecessary.
SLACK_RUN_SH="${PROJECT_DIR}/.claude/skills/slack-post/run.sh"
# The literal `~` is passed through to claude, which expands it per
# gitignore-style permission pattern semantics. Do not let the shell expand it.
# shellcheck disable=SC2088
NEWS_HISTORY_GLOB='~/.cache/claude-private-skills/**'
allowed_tools=(
  WebSearch
  WebFetch
  "Read(/**)"
  "Read(${NEWS_HISTORY_GLOB})"
  "Write(${NEWS_HISTORY_GLOB})"
  "Edit(${NEWS_HISTORY_GLOB})"
  "Bash(${SLACK_RUN_SH}:*)"
)

exit_code=0
for topic in "${topics[@]}"; do
  echo "=== $(date -Is) news-digest: $topic ==="
  prompt="Run the news-digest skill for topic \"${topic}\". "
  prompt+="If there is at least one new item, post the digest body to Slack via the "
  prompt+="slack-post skill with the --markdown flag. If there are zero new items, "
  prompt+="do not post anything to Slack and exit."

  if ! "$CLAUDE_BIN" -p "$prompt" --allowedTools "${allowed_tools[@]}"; then
    echo "warn: news-digest for '${topic}' exited non-zero (continuing with next topic)" >&2
    exit_code=1
  fi
done

exit "$exit_code"
