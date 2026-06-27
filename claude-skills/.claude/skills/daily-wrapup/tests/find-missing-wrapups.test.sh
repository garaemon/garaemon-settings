#!/usr/bin/env bash
#
# Unit test for find-missing-wrapups.sh. Builds a throwaway org-roam daily
# directory with a mix of wrapped, plain-note, and absent days, then asserts
# the script reports only the days that lack a daily-wrapup subtree, oldest
# first. Reads no real org data and touches no network.
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly skill_dir
readonly script="$skill_dir/find-missing-wrapups.sh"

work_dir="$(mktemp -d)"
readonly work_dir
trap 'rm -rf "$work_dir"' EXIT
readonly daily_dir="$work_dir/org-roam/daily"
mkdir -p "$daily_dir"

# BSD (macOS) date first, GNU date as the fallback — mirrors the script.
shift_day() {
  local offset="$1"
  date -v-"${offset}"d +%Y-%m-%d 2>/dev/null \
    || date -d "${offset} days ago" +%Y-%m-%d
}

write_wrapup_note() {
  local day="$1"
  cat >"$daily_dir/$day.org" <<EOF
:PROPERTIES:
:ID:       TESTID
:END:
#+title: $day
* $day Daily wrapup :claude:
:PROPERTIES:
:STATUS:   reviewed
:GENERATED_BY: claude-code/daily-wrapup
:END:
** GitHub
- did some things
EOF
}

write_plain_note() {
  local day="$1"
  cat >"$daily_dir/$day.org" <<EOF
:PROPERTIES:
:ID:       TESTID
:END:
#+title: $day
* a hand-written note with no wrap-up
EOF
}

# Arrange: yesterday is wrapped; 2 days ago is a plain note (no wrap-up);
# 3 days ago is absent entirely; 4..7 days ago are all wrapped.
yesterday="$(shift_day 1)"
two_days_ago="$(shift_day 2)"
three_days_ago="$(shift_day 3)"
write_wrapup_note "$yesterday"
write_plain_note "$two_days_ago"
for offset in 4 5 6 7; do
  write_wrapup_note "$(shift_day "$offset")"
done

# Act
got="$(ORG_DIR="$work_dir" "$script")"

# Assert: only the absent day and the plain-note day, oldest first.
want="$(printf '%s\n%s' "$three_days_ago" "$two_days_ago")"
if [[ "$got" != "$want" ]]; then
  echo "FAIL: unexpected missing-day list" >&2
  echo "want:" >&2
  echo "$want" >&2
  echo "got:" >&2
  echo "$got" >&2
  exit 1
fi

# A lookback argument above the one-week cap must still scan at most 7 days,
# so the result is unchanged when asking for 30.
got_capped="$(ORG_DIR="$work_dir" "$script" 30)"
if [[ "$got_capped" != "$want" ]]; then
  echo "FAIL: lookback was not capped at one week" >&2
  echo "got:" >&2
  echo "$got_capped" >&2
  exit 1
fi

echo "PASS: find-missing-wrapups reports only days without a wrap-up subtree"
