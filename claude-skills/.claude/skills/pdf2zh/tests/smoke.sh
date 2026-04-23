#!/usr/bin/env bash
# Smoke tests for the pdf2zh Docker image.
# Verifies the entrypoint's key-missing guard and that pdf2zh --help works
# when a dummy key is mounted. No real Gemini credentials or network are
# required.

set -euo pipefail

readonly IMAGE="${IMAGE:-pdf2zh:local}"

fail() {
  echo "smoke test failed: $*" >&2
  exit 1
}

test_missing_key_fails() {
  echo "Test: entrypoint exits non-zero when /secrets/gemini.key is missing"
  local output
  if output=$(docker run --rm "${IMAGE}" 2>&1); then
    fail "expected non-zero exit without key; got 0. output: ${output}"
  fi
  grep -q "gemini.key" <<<"${output}" \
    || fail "expected stderr to mention gemini.key; got: ${output}"
  echo "  OK"
}

test_empty_key_fails() {
  echo "Test: entrypoint exits non-zero when the key file is empty"
  local tmpdir
  tmpdir=$(mktemp -d)
  : >"${tmpdir}/gemini.key"
  # Grant world read so the container user (UID 1000) can read the test key
  # regardless of the host UID. Real keys go through run.sh which enforces 600.
  chmod 644 "${tmpdir}/gemini.key"
  local output
  local exit_status=0
  output=$(docker run --rm \
      -v "${tmpdir}/gemini.key:/secrets/gemini.key:ro" \
      "${IMAGE}" 2>&1) || exit_status=$?
  rm -rf "${tmpdir}"
  if (( exit_status == 0 )); then
    fail "expected non-zero exit with empty key; got 0. output: ${output}"
  fi
  grep -q "empty" <<<"${output}" \
    || fail "expected stderr to mention empty key; got: ${output}"
  echo "  OK"
}

test_help_with_dummy_key() {
  echo "Test: pdf2zh --help prints usage when a dummy key is mounted"
  local tmpdir
  tmpdir=$(mktemp -d)
  printf 'dummy-key-for-smoke-test' >"${tmpdir}/gemini.key"
  # Grant world read so the container user (UID 1000) can read the test key
  # regardless of the host UID. Real keys go through run.sh which enforces 600.
  chmod 644 "${tmpdir}/gemini.key"
  local output
  local exit_status=0
  output=$(docker run --rm \
      -v "${tmpdir}/gemini.key:/secrets/gemini.key:ro" \
      "${IMAGE}" --help 2>&1) || exit_status=$?
  rm -rf "${tmpdir}"
  if (( exit_status != 0 )); then
    fail "expected --help to exit 0; got ${exit_status}. output: ${output}"
  fi
  grep -Eiq "usage|options" <<<"${output}" \
    || fail "expected help output to mention 'usage' or 'options'; got: ${output}"
  echo "  OK"
}

main() {
  test_missing_key_fails
  test_empty_key_fails
  test_help_with_dummy_key
  echo "All pdf2zh smoke tests passed."
}

main "$@"
