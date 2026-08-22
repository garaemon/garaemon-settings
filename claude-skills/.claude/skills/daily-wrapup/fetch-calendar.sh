#!/usr/bin/env bash
#
# fetch-calendar.sh — print a day's events from the user's own (primary)
# Google Calendar, one per line as "start|end|summary|location".
#
# Reads through the gws-secure wrapper (1Password-backed, token-less). The
# read is scoped to calendarId=primary so imported and subscribed calendars
# (holidays, team feeds, @import calendars, a separate work calendar) are
# excluded — the wrap-up only wants the user's own calendar. It queries
# events.list with an explicit full-local-day window rather than the rolling
# `+agenda --today` helper, so events earlier in the day are not missed.
#
# Cancelled events and events the user themselves declined are dropped, since
# a wrap-up records what actually happened.
#
# Usage: fetch-calendar.sh [YYYY-MM-DD]   (default: today)
#
# Exits non-zero if the calendar cannot be read (e.g. a gws-secure auth
# failure); prints nothing and exits 0 when the day has no events.
set -euo pipefail

usage() {
  echo "Usage: fetch-calendar.sh [YYYY-MM-DD]   (default: today)"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

day="${1:-$(date +%Y-%m-%d)}"
readonly day
# Reject anything that is not a YYYY-MM-DD date up front. Without this, a
# leading-dash argument (e.g. -h) would flow into the date calls below and be
# swallowed as a date(1) option, producing a confusing "illegal option" error.
if [[ ! "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "fetch-calendar.sh: invalid date '$day' (expected YYYY-MM-DD)" >&2
  usage >&2
  exit 2
fi
readonly gws="${GWS_SECURE_BIN:-gws-secure}"
readonly calendar_id="primary"

# date +%z yields -0700; RFC3339 wants -07:00.
offset="$(date +%z | sed 's/\(..\)$/:\1/')"
readonly offset
# BSD (macOS) date first, GNU date as the fallback.
tomorrow="$(date -v+1d -j -f '%Y-%m-%d' "$day" +%Y-%m-%d 2>/dev/null \
  || date -d "$day +1 day" +%Y-%m-%d)"
readonly tomorrow

readonly time_min="${day}T00:00:00${offset}"
readonly time_max="${tomorrow}T00:00:00${offset}"

"$gws" calendar events list \
  --params "{\"calendarId\":\"${calendar_id}\",\"timeMin\":\"${time_min}\",\"timeMax\":\"${time_max}\",\"singleEvents\":true,\"orderBy\":\"startTime\",\"maxResults\":50}" \
  --format json \
  | jq -r '(.items // [])[]
      | select(.status != "cancelled")
      | select([.attendees[]? | select(.self == true) | .responseStatus]
               | (length == 0 or .[0] != "declined"))
      | "\(.start.dateTime // .start.date)|\(.end.dateTime // .end.date)|\(.summary // "(no title)")|\(.location // "")"'
