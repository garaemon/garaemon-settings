#!/usr/bin/env bash
# Smoke tests for the spotify-sheets Docker image.
# Verifies the image boots, enforces required env vars, and prints usage
# when invoked with no subcommand.

set -euo pipefail

readonly IMAGE="${IMAGE:-spotify-sheets:local}"

fail() {
  echo "smoke test failed: $*" >&2
  exit 1
}

run_image() {
  docker run --rm "$@" "${IMAGE}" 2>&1
}

test_missing_env_vars_fail() {
  echo "Test: image exits non-zero without env vars"
  local output
  if output=$(run_image); then
    fail "expected non-zero exit with no env vars; got 0. output: ${output}"
  fi
  grep -q "GOOGLE_SA_KEY_FILE" <<<"${output}" \
    || fail "expected stderr to mention GOOGLE_SA_KEY_FILE; got: ${output}"
  echo "  OK"
}

test_prints_usage_without_args() {
  echo "Test: image prints usage when given env vars but no subcommand"
  local output
  if output=$(run_image \
      -e GOOGLE_SA_KEY_FILE=/tmp/nonexistent \
      -e SPOTIFY_SPREADSHEET_ID=dummy); then
    fail "expected non-zero exit with no subcommand; got 0. output: ${output}"
  fi
  grep -q "Usage:" <<<"${output}" \
    || fail "expected 'Usage:' in output; got: ${output}"
  echo "  OK"
}

main() {
  test_missing_env_vars_fail
  test_prints_usage_without_args
  echo "All spotify-sheets smoke tests passed."
}

main "$@"
