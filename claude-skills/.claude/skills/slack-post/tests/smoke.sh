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

write_dummy_config() {
  local path="$1"
  local with_default_channel="$2"
  if [[ "${with_default_channel}" == "true" ]]; then
    printf '{"token":"xoxb-dummy","default_channel":"#dummy"}' > "${path}"
  else
    printf '{"token":"xoxb-dummy"}' > "${path}"
  fi
  # World-readable on purpose: the tmp file is bind-mounted into the
  # container under a non-root user whose UID may not match the host,
  # and the strict 600/400 enforcement lives in run.sh (not exercised
  # here). Real configs stay at mode 600 via run.sh's own check.
  chmod 644 "${path}"
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

test_missing_config_file_fails() {
  echo "Test: image exits non-zero when config file is missing"
  local output
  if output=$(docker run --rm \
      -e SLACK_CONFIG_FILE=/tmp/nonexistent \
      "${IMAGE}" \
      post --channel "#x" --text "hi" 2>&1); then
    fail "expected non-zero exit without config file; got 0. output: ${output}"
  fi
  grep -q "slack-post:" <<<"${output}" \
    || fail "expected slack-post error prefix; got: ${output}"
  echo "  OK"
}

test_missing_channel_without_default_fails() {
  echo "Test: post rejects missing --channel when config has no default_channel"
  local cfg
  cfg=$(mktemp)
  write_dummy_config "${cfg}" false
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --text "hi" 2>&1) || exit_code=$?
  rm -f "${cfg}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit without --channel and without default_channel; got 0. output: ${output}"
  fi
  grep -q -- "--channel is required" <<<"${output}" \
    || fail "expected '--channel is required' in output; got: ${output}"
  echo "  OK"
}

test_missing_text_fails() {
  echo "Test: post rejects missing --text and --stdin"
  local cfg
  cfg=$(mktemp)
  write_dummy_config "${cfg}" true
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --channel "#x" 2>&1) || exit_code=$?
  rm -f "${cfg}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit without --text/--stdin; got 0. output: ${output}"
  fi
  grep -q -- "--text or --stdin is required" <<<"${output}" \
    || fail "expected '--text or --stdin is required' in output; got: ${output}"
  echo "  OK"
}

test_invalid_json_config_fails() {
  echo "Test: post rejects config file that is not valid JSON"
  local cfg
  cfg=$(mktemp)
  printf 'not json' > "${cfg}"
  chmod 644 "${cfg}"
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --channel "#x" --text "hi" 2>&1) || exit_code=$?
  rm -f "${cfg}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit for invalid JSON config; got 0. output: ${output}"
  fi
  grep -q "not valid JSON" <<<"${output}" \
    || fail "expected 'not valid JSON' in output; got: ${output}"
  echo "  OK"
}

main() {
  test_prints_usage_without_args
  test_missing_config_file_fails
  test_missing_channel_without_default_fails
  test_missing_text_fails
  test_invalid_json_config_fails
  echo "All slack-post smoke tests passed."
}

main "$@"
