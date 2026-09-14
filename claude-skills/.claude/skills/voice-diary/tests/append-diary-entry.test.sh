#!/bin/bash
#
# Unit test for append-diary-entry.sh. Builds a throwaway org-roam daily
# directory and asserts the script creates a daily note with an org-roam
# header when none exists, appends a timestamped `:voice:` entry to an
# existing note without touching its earlier content, and rejects input that
# would corrupt the org structure. Reads no real org data and touches no
# network.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly skill_dir
readonly script="$skill_dir/append-diary-entry.sh"

work_dir="$(mktemp -d)"
readonly work_dir
trap 'rm -rf "$work_dir"' EXIT
readonly daily_dir="$work_dir/org-roam/daily"
mkdir -p "$daily_dir"

# 2026-08-15 is a Saturday, which pins the weekday abbreviation in the heading.
readonly day="2026-08-15"
readonly daily_file="$daily_dir/$day.org"

fail() {
  echo "FAIL: $1" >&2
  shift
  for line in "$@"; do
    echo "$line" >&2
  done
  exit 1
}

run_script() {
  ORG_DIR="$work_dir" ENTRY_TIME="12:29" "$script" "$@"
}

# Case 1: a missing daily note is created with the org-roam header, then the
# entry follows the header directly.
printf 'First line.\nSecond line.\n' | run_script "$day" "First entry" >/dev/null
[[ -f "$daily_file" ]] || fail "daily note was not created"

got_id="$(sed -n '2p' "$daily_file")"
if ! [[ "$got_id" =~ ^:ID:\ {7}[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$ ]]; then
  fail "second line is not an uppercase UUID :ID: property" "got: $got_id"
fi

want_created="$(cat <<WANT
:PROPERTIES:
$got_id
:END:
#+title: $day
* <$day Sat 12:29> First entry :voice:
First line.
Second line.
WANT
)"
got_created="$(cat "$daily_file")"
if [[ "$got_created" != "$want_created" ]]; then
  fail "created note differs from expected" "want:" "$want_created" "got:" "$got_created"
fi

# Case 2: appending to an existing note keeps the earlier content byte for
# byte, separates the new entry from it with one blank line, and reports the
# written path on stdout.
got_path="$(printf 'Only line.\n' | ORG_DIR="$work_dir" ENTRY_TIME="18:05" "$script" "$day" "Second entry")"
[[ "$got_path" == "$daily_file" ]] || fail "stdout is not the daily path" "got: $got_path"

want_appended="$(cat <<WANT
$want_created

* <$day Sat 18:05> Second entry :voice:
Only line.
WANT
)"
got_appended="$(cat "$daily_file")"
if [[ "$got_appended" != "$want_appended" ]]; then
  fail "appended note differs from expected" "want:" "$want_appended" "got:" "$got_appended"
fi

# Case 3: a note whose last line lacks a newline still gets a well-formed
# heading on its own line.
readonly other_day="2026-08-16"
readonly other_file="$daily_dir/$other_day.org"
printf ':PROPERTIES:\n:ID:       TESTID\n:END:\n#+title: %s\n* old heading\nold body' "$other_day" >"$other_file"
printf 'New body.\n' | run_script "$other_day" "Third entry" >/dev/null
want_fixed="$(cat <<WANT
:PROPERTIES:
:ID:       TESTID
:END:
#+title: $other_day
* old heading
old body

* <$other_day Sun 12:29> Third entry :voice:
New body.
WANT
)"
got_fixed="$(cat "$other_file")"
if [[ "$got_fixed" != "$want_fixed" ]]; then
  fail "note without trailing newline was appended badly" "want:" "$want_fixed" "got:" "$got_fixed"
fi

# Case 4: a body line starting with `*` would become an org heading, so the
# script refuses it and leaves the note unchanged.
before="$(cat "$daily_file")"
if printf 'fine\n* not fine\n' | run_script "$day" "Bad body" >/dev/null 2>&1; then
  fail "body with a leading-star line was accepted"
fi
[[ "$(cat "$daily_file")" == "$before" ]] || fail "rejected body still modified the note"

# Case 5: an empty body is refused for the same reason (a heading with no
# diary text is noise).
if printf '' | run_script "$day" "Empty body" >/dev/null 2>&1; then
  fail "empty body was accepted"
fi

# Case 6: a malformed day is refused before anything is written.
if printf 'x\n' | run_script "15-08-2026" "Bad day" >/dev/null 2>&1; then
  fail "malformed day was accepted"
fi
[[ ! -f "$daily_dir/15-08-2026.org" ]] || fail "malformed day created a file"

# Case 7: a missing daily directory is an error, not a silent mkdir.
if printf 'x\n' | ORG_DIR="$work_dir/nope" ENTRY_TIME="12:29" "$script" "$day" "No dir" >/dev/null 2>&1; then
  fail "missing daily directory was accepted"
fi

echo "PASS: append-diary-entry creates, appends, and validates diary entries"
