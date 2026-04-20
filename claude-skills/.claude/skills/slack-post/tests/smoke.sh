#!/usr/bin/env bash
# Smoke tests for the slack-post Docker image.
# Verifies the image boots, prints usage with no args, and exits non-zero
# with a clear error when required inputs are missing. No real Slack
# credentials or network are required.

set -euo pipefail

readonly IMAGE="${IMAGE:-slack-post:local}"

fail() {
  echo "smoke test failed: $*" >&2
  exit 1
}

test_prints_usage_without_args() {
  echo "Test: image prints usage with no subcommand"
  local output
  if output=$(docker run --rm "${IMAGE}" 2>&1); then
    fail "expected non-zero exit with no subcommand; got 0. output: ${output}"
  fi
  grep -q "Usage:" <<<"${output}" \
    || fail "expected 'Usage:' in output; got: ${output}"
  echo "  OK"
}

test_missing_token_file_fails() {
  echo "Test: image exits non-zero when token file is missing"
  local output
  if output=$(docker run --rm \
      -e SLACK_TOKEN_FILE=/tmp/nonexistent \
      "${IMAGE}" \
      post --channel "#x" --text "hi" 2>&1); then
    fail "expected non-zero exit without token file; got 0. output: ${output}"
  fi
  grep -q "slack-post:" <<<"${output}" \
    || fail "expected slack-post error prefix; got: ${output}"
  echo "  OK"
}

test_missing_channel_fails() {
  echo "Test: post rejects missing --channel"
  local output
  if output=$(docker run --rm "${IMAGE}" post --text "hi" 2>&1); then
    fail "expected non-zero exit without --channel; got 0. output: ${output}"
  fi
  grep -q -- "--channel is required" <<<"${output}" \
    || fail "expected '--channel is required' in output; got: ${output}"
  echo "  OK"
}

test_missing_text_fails() {
  echo "Test: post rejects missing --text and --stdin"
  local output
  if output=$(docker run --rm "${IMAGE}" post --channel "#x" 2>&1); then
    fail "expected non-zero exit without --text/--stdin; got 0. output: ${output}"
  fi
  grep -q -- "--text or --stdin is required" <<<"${output}" \
    || fail "expected '--text or --stdin is required' in output; got: ${output}"
  echo "  OK"
}

main() {
  test_prints_usage_without_args
  test_missing_token_file_fails
  test_missing_channel_fails
  test_missing_text_fails
  echo "All slack-post smoke tests passed."
}

main "$@"
