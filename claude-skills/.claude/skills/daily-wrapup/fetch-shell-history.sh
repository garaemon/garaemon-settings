#!/usr/bin/env bash
#
# fetch-shell-history.sh — print the shell commands the user ran on a given
# day, one per line as "time|exit|directory|command", read via atuin.
#
# Before querying, it syncs from the user's atuin server so commands run on
# other machines that day are included too. The sync is best-effort: if it
# fails (offline, logged out), the script warns on stderr and continues with
# the local history database rather than failing the whole wrap-up.
#
# The window is a full local calendar day [DAY 00:00, DAY+1 00:00) in the
# host's local timezone, expressed as RFC3339 bounds so atuin's
# --after/--before filter (which compares against UTC-stored timestamps) lines
# up with the local day exactly — the same trick fetch-calendar.sh uses for the
# calendar window.
#
# atuin's history database and its sync/encryption keys live on the host under
# the user's home directory and are host-bound, so — like gh, git, and
# gws-secure elsewhere in this skill — atuin runs directly on the host rather
# than inside a container.
#
# Usage: fetch-shell-history.sh [YYYY-MM-DD]   (default: today)
#
# Exits non-zero only when atuin is unavailable or the query itself fails;
# prints nothing and exits 0 when the day has no commands.
set -euo pipefail

day="${1:-$(date +%Y-%m-%d)}"
readonly day
readonly atuin="${ATUIN_BIN:-atuin}"

if ! command -v "$atuin" >/dev/null 2>&1; then
  echo "fetch-shell-history.sh: atuin not found on PATH" >&2
  exit 1
fi

# Pull the day's commands from the server first so entries typed on other
# machines are included. Best-effort: a sync failure (offline, logged out)
# must not abort the wrap-up, so warn and fall back to the local database.
if ! "$atuin" sync >/dev/null 2>&1; then
  echo "fetch-shell-history.sh: atuin sync failed; using local history only" >&2
fi

# date +%z yields -0700; RFC3339 wants -07:00.
offset="$(date +%z | sed 's/\(..\)$/:\1/')"
readonly offset
# BSD (macOS) date first, GNU date as the fallback.
tomorrow="$(date -v+1d -j -f '%Y-%m-%d' "$day" +%Y-%m-%d 2>/dev/null \
  || date -d "$day +1 day" +%Y-%m-%d)"
readonly tomorrow

# --print0 separates records with a NUL so a multi-line command (heredoc,
# inline script) stays one record. Flatten each record's internal newlines to
# spaces, then turn the NUL separators into newlines, so the output is exactly
# one command per line for the summarizing subagent. {command} is the last
# field and may itself contain '|'.
#
# atuin search is grep-like: it exits 1 when nothing matches the window. That
# is an empty day, not an error, so tolerate the non-zero exit here rather than
# letting `set -e` abort a quiet day.
"$atuin" search \
  --after "${day}T00:00:00${offset}" \
  --before "${tomorrow}T00:00:00${offset}" \
  --print0 --format "{time}|{exit}|{directory}|{command}" \
  | tr '\n' ' ' | tr '\0' '\n' \
  || true
