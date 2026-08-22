#!/usr/bin/env bash
#
# Smoke test for gws-secure. Exercises the deterministic failure paths that do
# not require 1Password, the network, or a browser:
#   - a missing required dependency fails fast with a clear message.
#
# The OAuth and 1Password paths are verified live during bootstrap + first use,
# not here.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WRAPPER="$SCRIPT_DIR/gws-secure"

fail() {
  printf 'smoke: FAIL - %s\n' "$1" >&2
  exit 1
}

# With an empty PATH the very first dependency check (op) must fail non-zero
# and the message must name the missing command. The wrapper is launched via
# bash's absolute path (resolved before PATH is cleared) so the interpreter is
# still found while the script's internal `command -v` lookups see no PATH.
bash_abs="$(command -v bash)"
output="$(PATH="" "$bash_abs" "$WRAPPER" gmail users getProfile 2>&1)" && status=0 || status=$?
[ "$status" -ne 0 ] || fail "expected non-zero exit when dependencies are missing"
printf '%s' "$output" | grep -q "required command not found" \
  || fail "expected a 'required command not found' message, got: $output"

printf 'smoke: OK\n'
