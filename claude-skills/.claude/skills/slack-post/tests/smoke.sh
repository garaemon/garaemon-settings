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
  grep -q -- "One of --text, --stdin, --text-file is required" <<<"${output}" \
    || fail "expected '--text or --stdin is required' in output; got: ${output}"
  echo "  OK"
}

test_markdown_is_boolean_flag() {
  # --markdown takes no value; the parser must not consume the next arg as
  # its value. If boolean-flag handling regresses, --markdown would swallow
  # --channel and the run would fail with "--channel is required" before
  # reaching the --text/--stdin check this test asserts on.
  echo "Test: --markdown is parsed as a boolean flag"
  local cfg
  cfg=$(mktemp)
  write_dummy_config "${cfg}" true
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --markdown --channel "#x" 2>&1) || exit_code=$?
  rm -f "${cfg}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit; got 0. output: ${output}"
  fi
  grep -q -- "One of --text, --stdin, --text-file is required" <<<"${output}" \
    || fail "expected '--text or --stdin is required' (--markdown should be a boolean flag); got: ${output}"
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

test_text_and_text_file_mutually_exclusive() {
  # The inner CLI must reject combining --text with --text-file even when
  # both happen to be present on the command line. The wrapper rewrites
  # the host path on --text-file but does not strip --text, so this is a
  # real failure mode an agent could hit.
  echo "Test: post rejects --text combined with --text-file"
  local cfg
  cfg=$(mktemp)
  write_dummy_config "${cfg}" true
  local body
  body=$(mktemp)
  printf 'hello\n' > "${body}"
  chmod 644 "${body}"
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -v "${body}:/inputs/body.md:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --channel "#x" --text "hi" --text-file /inputs/body.md 2>&1) \
    || exit_code=$?
  rm -f "${cfg}" "${body}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit when --text and --text-file are both set; got 0. output: ${output}"
  fi
  grep -q "exactly one of --text" <<<"${output}" \
    || fail "expected 'exactly one of --text' in output; got: ${output}"
  echo "  OK"
}

test_text_file_empty_body_fails() {
  # An empty body file is almost always a caller bug. Surface it loudly
  # rather than silently posting a zero-character message.
  echo "Test: post rejects --text-file pointing at an empty file"
  local cfg
  cfg=$(mktemp)
  write_dummy_config "${cfg}" true
  local body
  body=$(mktemp)
  : > "${body}"
  chmod 644 "${body}"
  local output
  local exit_code=0
  output=$(docker run --rm \
    -v "${cfg}:/secrets/config.json:ro" \
    -v "${body}:/inputs/body.md:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE}" post --channel "#x" --text-file /inputs/body.md 2>&1) \
    || exit_code=$?
  rm -f "${cfg}" "${body}"
  if [[ "${exit_code}" == "0" ]]; then
    fail "expected non-zero exit for empty --text-file; got 0. output: ${output}"
  fi
  grep -q "empty message body" <<<"${output}" \
    || fail "expected 'empty message body' in output; got: ${output}"
  echo "  OK"
}

main() {
  test_prints_usage_without_args
  test_missing_config_file_fails
  test_missing_channel_without_default_fails
  test_missing_text_fails
  test_markdown_is_boolean_flag
  test_invalid_json_config_fails
  test_text_and_text_file_mutually_exclusive
  test_text_file_empty_body_fails
  echo "All slack-post smoke tests passed."
}

main "$@"
