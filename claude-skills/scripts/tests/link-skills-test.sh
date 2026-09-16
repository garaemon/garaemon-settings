#!/bin/bash
set -euo pipefail

# Tests for scripts/link-skills.sh. Every case runs against a throwaway target
# directory, so nothing here touches ~/.claude/skills.
#
# Usage: bash scripts/tests/link-skills-test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LINK_SKILLS="$SCRIPT_DIR/../link-skills.sh"
# Resolved, because link-skills.sh records the resolved path in every link it
# creates and the tests below compare against it.
SKILLS_DIR="$(cd "$SCRIPT_DIR/../../skills" && pwd)"
readonly SKILLS_DIR

WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
# shellcheck disable=SC2064
trap "rm -rf '$WORK_DIR'" EXIT

failure_count=0

report_failure() {
  printf 'FAIL: %s\n' "$*" >&2
  failure_count=$((failure_count + 1))
}

expect_equal() {
  local expected="$1" actual="$2" description="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'ok: %s\n' "$description"
  else
    report_failure "$description (expected '$expected', got '$actual')"
  fi
}

# Runs link-skills.sh against a fresh target directory, printing its exit status
# on the first line and its stdout after it.
run_link_skills() {
  local target="$1"
  local status=0
  local output
  output="$("$LINK_SKILLS" "$target" 2>/dev/null)" || status=$?
  printf '%s\n%s\n' "$status" "$output"
}

test_links_every_skill_into_an_empty_directory() {
  local target="$WORK_DIR/empty"
  local result skill_count linked_count
  result="$(run_link_skills "$target")"
  expect_equal 0 "$(printf '%s' "$result" | head -n 1)" "an empty target succeeds"

  skill_count="$(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)"
  linked_count="$(find "$target" -maxdepth 1 -type l | wc -l)"
  expect_equal "$skill_count" "$linked_count" "every skill is linked"
}

test_relinks_without_complaint() {
  local target="$WORK_DIR/repeat"
  run_link_skills "$target" >/dev/null
  expect_equal 0 "$(run_link_skills "$target" | head -n 1)" "a second run succeeds"
}

test_keeps_a_symlink_pointing_elsewhere() {
  local target="$WORK_DIR/foreign"
  mkdir -p "$target"
  ln -s /dev/null "$target/technical-writing"
  run_link_skills "$target" >/dev/null
  expect_equal /dev/null "$(readlink "$target/technical-writing")" \
    "a symlink pointing outside the repository survives"
}

test_keeps_a_real_directory() {
  local target="$WORK_DIR/occupied"
  mkdir -p "$target/technical-writing"
  run_link_skills "$target" >/dev/null
  if [ -L "$target/technical-writing" ]; then
    report_failure "a real directory was replaced by a link"
  else
    printf 'ok: a real directory survives\n'
  fi
}

test_fails_when_nothing_could_be_linked() {
  local target="$WORK_DIR/all-taken"
  local skill_path
  mkdir -p "$target"
  for skill_path in "$SKILLS_DIR"/*; do
    [ -f "$skill_path/SKILL.md" ] || continue
    mkdir -p "$target/$(basename "$skill_path")"
  done
  expect_equal 1 "$(run_link_skills "$target" | head -n 1)" \
    "linking nothing fails, so an unattended setup notices"
}

test_removes_a_link_to_a_skill_that_is_gone() {
  local target="$WORK_DIR/stale"
  run_link_skills "$target" >/dev/null
  ln -s "$SKILLS_DIR/removed-skill" "$target/removed-skill"
  run_link_skills "$target" >/dev/null
  if [ -L "$target/removed-skill" ]; then
    report_failure "a link to a skill that no longer exists was left behind"
  else
    printf 'ok: a link to a skill that no longer exists is removed\n'
  fi
}

test_keeps_a_link_into_another_tree() {
  local target="$WORK_DIR/other-tree"
  run_link_skills "$target" >/dev/null
  ln -s /nowhere/at/all "$target/someone-elses-skill"
  run_link_skills "$target" >/dev/null
  if [ -L "$target/someone-elses-skill" ]; then
    printf 'ok: a dangling link outside this repository is left alone\n'
  else
    report_failure "a dangling link outside this repository was removed"
  fi
}

test_links_every_skill_into_an_empty_directory
test_relinks_without_complaint
test_removes_a_link_to_a_skill_that_is_gone
test_keeps_a_link_into_another_tree
test_keeps_a_symlink_pointing_elsewhere
test_keeps_a_real_directory
test_fails_when_nothing_could_be_linked

if [ "$failure_count" -gt 0 ]; then
  printf '%d test(s) failed\n' "$failure_count" >&2
  exit 1
fi
printf 'all tests passed\n'
