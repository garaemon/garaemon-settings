#!/usr/bin/env bash
# Wrapper that runs the slack-post CLI inside a hardened Docker container.
# Mounts the Slack bot token file read-only and passes all args through.

set -euo pipefail

readonly IMAGE_TAG="slack-post:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_TOKEN_PATH="${HOME}/.config/slack-post/token"
readonly TOKEN_PATH="${SLACK_TOKEN_FILE:-${DEFAULT_TOKEN_PATH}}"

die() {
  echo "run.sh: error: $*" >&2
  exit 1
}

get_file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

ensure_image_exists() {
  if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
    die "Docker image '${IMAGE_TAG}' not found. Build it first:
  docker build -t ${IMAGE_TAG} \"${SCRIPT_DIR}\""
  fi
}

ensure_token_file_safe() {
  if [[ ! -e "${TOKEN_PATH}" ]]; then
    die "Slack token file not found at ${TOKEN_PATH}. Place it there or override with SLACK_TOKEN_FILE."
  fi
  if [[ -L "${TOKEN_PATH}" ]]; then
    die "Slack token file must be a regular file, not a symlink: ${TOKEN_PATH}"
  fi
  if [[ ! -f "${TOKEN_PATH}" ]]; then
    die "Slack token file must be a regular file: ${TOKEN_PATH}"
  fi
  local mode
  mode=$(get_file_mode "${TOKEN_PATH}")
  if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
    die "Slack token file ${TOKEN_PATH} must be mode 600 or 400 (current: ${mode}). Run: chmod 600 ${TOKEN_PATH}"
  fi
}

wants_stdin() {
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "--stdin" ]]; then
      return 0
    fi
  done
  return 1
}

run_container() {
  local stdin_flags=()
  if wants_stdin "$@"; then
    stdin_flags=(-i)
  fi
  docker run --rm \
    "${stdin_flags[@]}" \
    --network bridge \
    --read-only --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 256m --cpus 0.5 \
    -v "${TOKEN_PATH}:/secrets/token:ro" \
    -e SLACK_TOKEN_FILE=/secrets/token \
    "${IMAGE_TAG}" "$@"
}

main() {
  ensure_image_exists
  ensure_token_file_safe
  run_container "$@"
}

main "$@"
