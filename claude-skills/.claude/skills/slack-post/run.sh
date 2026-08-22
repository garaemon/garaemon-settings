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

# Container path the host file is bind-mounted at when --text-file is used.
readonly TEXT_FILE_CONTAINER_PATH="/inputs/body.md"

# Globals populated by parse_text_file_arg from the caller's args.
TEXT_FILE_HOST_PATH=""
REWRITTEN_ARGS=()

# Walk the args once. If --text-file <path> appears, capture the host path
# and rewrite that arg to the container-side path so the inner CLI reads
# the bind-mounted file, not the host filesystem.
parse_text_file_arg() {
  TEXT_FILE_HOST_PATH=""
  REWRITTEN_ARGS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --text-file)
        if [[ $# -lt 2 ]]; then
          die "--text-file requires a path argument."
        fi
        if [[ -n "${TEXT_FILE_HOST_PATH}" ]]; then
          die "--text-file may only be passed once."
        fi
        TEXT_FILE_HOST_PATH="$2"
        REWRITTEN_ARGS+=("--text-file" "${TEXT_FILE_CONTAINER_PATH}")
        shift 2
        ;;
      *)
        REWRITTEN_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

ensure_text_file_safe() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    die "--text-file path does not exist: ${path}"
  fi
  if [[ -L "${path}" ]]; then
    die "--text-file path must be a regular file, not a symlink: ${path}"
  fi
  if [[ ! -f "${path}" ]]; then
    die "--text-file path must be a regular file: ${path}"
  fi
  if [[ ! -r "${path}" ]]; then
    die "--text-file path is not readable: ${path}"
  fi
}

run_container() {
  local stdin_flags=()
  if wants_stdin "$@"; then
    stdin_flags=(-i)
  fi
  local text_file_mount=()
  if [[ -n "${TEXT_FILE_HOST_PATH}" ]]; then
    text_file_mount=(-v "${TEXT_FILE_HOST_PATH}:${TEXT_FILE_CONTAINER_PATH}:ro")
  fi
  docker run --rm \
    "${stdin_flags[@]}" \
    "${text_file_mount[@]}" \
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
  parse_text_file_arg "$@"
  if [[ -n "${TEXT_FILE_HOST_PATH}" ]]; then
    ensure_text_file_safe "${TEXT_FILE_HOST_PATH}"
  fi
  run_container "${REWRITTEN_ARGS[@]}"
}

main "$@"
