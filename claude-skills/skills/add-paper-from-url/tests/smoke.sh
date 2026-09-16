#!/usr/bin/env bash
# Smoke tests for the add-paper-from-url Docker image.
# Confirms the image boots, rejects unknown/missing subcommands, prints usage,
# and enforces the workspace-path constraint for `fetch`.

set -euo pipefail

readonly IMAGE="${IMAGE:-add-paper-from-url:local}"

fail() {
  echo "smoke test failed: $*" >&2
  exit 1
}

run_image() {
  docker run --rm "${IMAGE}" "$@" 2>&1
}

test_prints_usage_without_args() {
  echo "Test: image prints usage when given no args"
  local output
  if output=$(run_image); then
    fail "expected non-zero exit with no args; got 0. output: ${output}"
  fi
  grep -q "Usage:" <<<"${output}" \
    || fail "expected 'Usage:' in output; got: ${output}"
  echo "  OK"
}

test_help_subcommand() {
  echo "Test: image prints usage on 'help'"
  local output
  output=$(run_image help)
  grep -q "Usage:" <<<"${output}" \
    || fail "expected 'Usage:' in output; got: ${output}"
  echo "  OK"
}

test_unknown_subcommand_fails() {
  echo "Test: image exits non-zero for unknown subcommand"
  local output
  if output=$(run_image bogus); then
    fail "expected non-zero exit for unknown subcommand; got 0. output: ${output}"
  fi
  grep -q "unknown subcommand" <<<"${output}" \
    || fail "expected 'unknown subcommand' in output; got: ${output}"
  echo "  OK"
}

test_fetch_rejects_path_outside_workspace() {
  echo "Test: fetch rejects output paths outside /tmp/paperpile-add"
  local output
  if output=$(run_image fetch https://example.com/foo.pdf /tmp/evil.pdf); then
    fail "expected non-zero exit for workspace escape; got 0. output: ${output}"
  fi
  grep -q "must be under" <<<"${output}" \
    || fail "expected 'must be under' in output; got: ${output}"
  echo "  OK"
}

test_fetch_rejects_dotdot_traversal() {
  echo "Test: fetch rejects output paths with '..' components"
  local output
  if output=$(run_image fetch \
      https://example.com/foo.pdf \
      /tmp/paperpile-add/../evil.pdf); then
    fail "expected non-zero exit for '..' traversal; got 0. output: ${output}"
  fi
  grep -q "must not contain '..'" <<<"${output}" \
    || fail "expected \"must not contain '..'\" in output; got: ${output}"
  echo "  OK"
}

test_fetch_rejects_wrong_arity() {
  echo "Test: fetch rejects wrong arg count"
  local output
  if output=$(run_image fetch only-one-arg); then
    fail "expected non-zero exit for wrong arity; got 0. output: ${output}"
  fi
  grep -q "expected <url> <output-path>" <<<"${output}" \
    || fail "expected 'expected <url> <output-path>' in output; got: ${output}"
  echo "  OK"
}

test_paperpile_proxy_help() {
  echo "Test: paperpile subcommand proxies to the CLI (--help)"
  local output
  output=$(run_image paperpile --help)
  grep -q "paperpile \[command\]" <<<"${output}" \
    || fail "expected paperpile CLI usage text; got: ${output}"
  echo "  OK"
}

main() {
  test_prints_usage_without_args
  test_help_subcommand
  test_unknown_subcommand_fails
  test_fetch_rejects_path_outside_workspace
  test_fetch_rejects_dotdot_traversal
  test_fetch_rejects_wrong_arity
  test_paperpile_proxy_help
  echo "All add-paper-from-url smoke tests passed."
}

main "$@"
