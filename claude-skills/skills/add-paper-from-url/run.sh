#!/usr/bin/env bash
# Wrapper that runs the paperpile CLI (and curl-based PDF fetch) inside a
# hardened Docker container. Mounts the Paperpile config read-only and a
# dedicated workspace directory read-write for PDF downloads.

set -euo pipefail

readonly IMAGE_TAG="add-paper-from-url:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_CONFIG_PATH="${HOME}/.config/paperpile/config.yaml"
readonly CONFIG_PATH="${PAPERPILE_CONFIG_FILE:-${DEFAULT_CONFIG_PATH}}"
readonly DEFAULT_WORKSPACE="/tmp/paperpile-add"
readonly WORKSPACE_HOST="${PAPERPILE_WORKSPACE:-${DEFAULT_WORKSPACE}}"
readonly WORKSPACE_CONTAINER="/tmp/paperpile-add"

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

ensure_config_safe() {
  if [[ ! -e "${CONFIG_PATH}" ]]; then
    die "Paperpile config not found at ${CONFIG_PATH}. Run \`paperpile login\` on the host, or override with PAPERPILE_CONFIG_FILE."
  fi
  if [[ -L "${CONFIG_PATH}" ]]; then
    die "Paperpile config must be a regular file, not a symlink: ${CONFIG_PATH}"
  fi
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    die "Paperpile config must be a regular file: ${CONFIG_PATH}"
  fi
  local mode
  mode=$(get_file_mode "${CONFIG_PATH}")
  if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
    die "Paperpile config ${CONFIG_PATH} must be mode 600 or 400 (current: ${mode}). Run: chmod 600 ${CONFIG_PATH}"
  fi
}

ensure_workspace_exists() {
  mkdir -p "${WORKSPACE_HOST}"
}

run_container() {
  docker run --rm \
    --network bridge \
    --read-only --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 256m --cpus 0.5 \
    -v "${CONFIG_PATH}:/home/paperpile/.config/paperpile/config.yaml:ro" \
    -v "${WORKSPACE_HOST}:${WORKSPACE_CONTAINER}:rw" \
    "${IMAGE_TAG}" "$@"
}

main() {
  ensure_image_exists
  ensure_config_safe
  ensure_workspace_exists
  run_container "$@"
}

main "$@"
