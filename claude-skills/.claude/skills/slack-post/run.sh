#!/usr/bin/env bash
# Wrapper that runs the slack-post CLI inside a hardened Docker container.
# Mounts the JSON config file (bot token + default channel) read-only and
# passes all args through.

set -euo pipefail

readonly IMAGE_TAG="slack-post:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_CONFIG_PATH="${HOME}/.config/slack-post/config.json"
readonly CONFIG_PATH="${SLACK_CONFIG_FILE:-${DEFAULT_CONFIG_PATH}}"

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

ensure_config_file_safe() {
  if [[ ! -e "${CONFIG_PATH}" ]]; then
    die "Slack config file not found at ${CONFIG_PATH}. Place it there or override with SLACK_CONFIG_FILE."
  fi
  if [[ -L "${CONFIG_PATH}" ]]; then
    die "Slack config file must be a regular file, not a symlink: ${CONFIG_PATH}"
  fi
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    die "Slack config file must be a regular file: ${CONFIG_PATH}"
  fi
  local mode
  mode=$(get_file_mode "${CONFIG_PATH}")
  if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
    die "Slack config file ${CONFIG_PATH} must be mode 600 or 400 (current: ${mode}). Run: chmod 600 ${CONFIG_PATH}"
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
    -v "${CONFIG_PATH}:/secrets/config.json:ro" \
    -e SLACK_CONFIG_FILE=/secrets/config.json \
    "${IMAGE_TAG}" "$@"
}

main() {
  ensure_image_exists
  ensure_config_file_safe
  run_container "$@"
}

main "$@"
