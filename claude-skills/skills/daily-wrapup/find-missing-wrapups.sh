#!/usr/bin/env bash
#
# find-missing-wrapups.sh — list recent days that have no daily-wrapup note.
#
# Scans the org-roam daily directory for the past N days ending yesterday and
# prints each YYYY-MM-DD whose daily file is either absent or present without a
# daily-wrapup subtree. Today is skipped because the day is not over yet. The
# lookback defaults to 7 and is capped at 7 ("at most one week"). Output is one
# date per line, oldest first; nothing is printed when every recent day already
# has a wrap-up.
#
# This reads only local org files — no network, no credentials, no third-party
# CLI — so it runs on the host rather than in a container.
#
# Usage: find-missing-wrapups.sh [LOOKBACK_DAYS]   (default 7, max 7)
#
# Environment:
#   ORG_DIR   org repository root (default: $HOME/org)
set -euo pipefail

readonly max_lookback=7
requested_lookback="${1:-$max_lookback}"

if ! [[ "$requested_lookback" =~ ^[0-9]+$ ]] || (( requested_lookback < 1 )); then
  echo "find-missing-wrapups.sh: LOOKBACK_DAYS must be a positive integer" >&2
  exit 2
fi

lookback="$requested_lookback"
if (( lookback > max_lookback )); then
  lookback="$max_lookback"
fi
readonly lookback

readonly org_dir="${ORG_DIR:-$HOME/org}"
readonly daily_dir="$org_dir/org-roam/daily"

if [[ ! -d "$daily_dir" ]]; then
  echo "find-missing-wrapups.sh: daily directory not found: $daily_dir" >&2
  exit 1
fi

# The provenance line a wrap-up writes into the note's property drawer. Match
# both the current daily-wrapup marker and the legacy daily-digest one — the
# skill was renamed (daily-digest -> daily-wrapup) and pre-rename notes are
# wrap-ups too, so already-wrapped days must not be re-flagged. A file with
# neither marker has no wrap-up subtree.
readonly wrapup_marker='GENERATED_BY: claude-code/daily-(wrapup|digest)'

# BSD (macOS) date first, GNU date as the fallback — mirrors fetch-calendar.sh.
shift_day() {
  local offset="$1"
  date -v-"${offset}"d +%Y-%m-%d 2>/dev/null \
    || date -d "${offset} days ago" +%Y-%m-%d
}

for (( offset = lookback; offset >= 1; offset-- )); do
  day="$(shift_day "$offset")"
  daily_file="$daily_dir/$day.org"
  if [[ ! -f "$daily_file" ]] || ! grep -qE "$wrapup_marker" "$daily_file"; then
    echo "$day"
  fi
done
