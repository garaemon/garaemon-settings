#!/bin/bash
#
# append-diary-entry.sh — append one diary entry to an org-roam daily note.
#
# Reads the entry body from stdin and appends it to
# $ORG_DIR/org-roam/daily/DAY.org under a heading shaped like the one the
# user's Emacs capture template produces (`* <YYYY-MM-DD Dow HH:MM> TITLE`),
# tagged `:voice:` so dictated entries stay distinguishable from typed ones.
# When the daily note does not exist yet, the script creates it with the
# org-roam header (`:ID:` property drawer and `#+title:`). Existing content
# is never rewritten; the entry is only ever appended.
#
# The script prints the path of the daily note on success. It reads only
# local org files — no network, no credentials, no third-party CLI — so it
# runs on the host rather than in a container.
#
# Usage: append-diary-entry.sh DAY TITLE < body
#   DAY    YYYY-MM-DD
#   TITLE  one-line heading text (no leading stars, no tags)
#   body   diary text on stdin; lines must not start with `*`, because such
#          a line would become an org heading and split the entry
#
# Environment:
#   ORG_DIR     org repository root (default: $HOME/org)
#   ENTRY_TIME  HH:MM stamped into the heading (default: current time)
set -euo pipefail

readonly script_name="append-diary-entry.sh"

die() {
  echo "$script_name: $1" >&2
  exit "${2:-1}"
}

if (( $# != 2 )); then
  die "usage: $script_name DAY TITLE < body" 2
fi

readonly day="$1"
readonly title="$2"

if ! [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  die "DAY must be YYYY-MM-DD, got: $day" 2
fi
if [[ -z "$title" || "$title" == *$'\n'* ]]; then
  die "TITLE must be one non-empty line" 2
fi

readonly org_dir="${ORG_DIR:-$HOME/org}"
readonly daily_dir="$org_dir/org-roam/daily"
readonly daily_file="$daily_dir/$day.org"

if [[ ! -d "$daily_dir" ]]; then
  die "daily directory not found: $daily_dir"
fi

body="$(cat)"
readonly body
if [[ -z "${body//[[:space:]]/}" ]]; then
  die "body on stdin is empty" 2
fi
if grep -q '^\*' <<<"$body"; then
  die "body lines must not start with '*' (use '-' bullets instead)" 2
fi

# BSD (macOS) date first, GNU date as the fallback. LC_ALL=C keeps the weekday
# abbreviation English (Sat, not 土) to match the existing notes.
weekday_of() {
  local target_day="$1"
  LC_ALL=C date -j -f %Y-%m-%d "$target_day" +%a 2>/dev/null \
    || LC_ALL=C date -d "$target_day" +%a
}

# Existing notes carry uppercase hyphenated UUIDs, so every source is
# normalised to that form. uuidgen is absent on some minimal Linux hosts.
generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    python3 -c 'import uuid; print(uuid.uuid4())'
  fi | tr '[:lower:]' '[:upper:]'
}

weekday="$(weekday_of "$day")" || die "cannot resolve weekday for $day"
readonly weekday
readonly entry_time="${ENTRY_TIME:-$(date +%H:%M)}"
if ! [[ "$entry_time" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
  die "ENTRY_TIME must be HH:MM, got: $entry_time" 2
fi

if [[ ! -f "$daily_file" ]]; then
  printf ':PROPERTIES:\n:ID:       %s\n:END:\n#+title: %s\n' \
    "$(generate_uuid)" "$day" >"$daily_file"
else
  # A note whose last line has no newline would otherwise swallow the new
  # heading into that line, and a separating blank line keeps entries
  # visually apart the way Emacs capture leaves them.
  if [[ -n "$(tail -c 1 "$daily_file")" ]]; then
    printf '\n' >>"$daily_file"
  fi
  printf '\n' >>"$daily_file"
fi

printf '* <%s %s %s> %s :voice:\n%s\n' \
  "$day" "$weekday" "$entry_time" "$title" "$body" >>"$daily_file"

echo "$daily_file"
