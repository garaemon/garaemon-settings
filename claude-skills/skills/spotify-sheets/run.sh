#!/usr/bin/env bash
# Wrapper that runs the spotify-sheets CLI inside a hardened Docker container.
# Mounts the Google service account key read-only and passes all args through.

set -euo pipefail

readonly IMAGE_TAG="spotify-sheets:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_KEY_PATH="${HOME}/.config/spotify-sheets/sa.json"
readonly KEY_PATH="${GOOGLE_SA_KEY_FILE:-${DEFAULT_KEY_PATH}}"

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

ensure_spreadsheet_id() {
  if [[ -z "${SPOTIFY_SPREADSHEET_ID:-}" ]]; then
    die "SPOTIFY_SPREADSHEET_ID env var is not set."
  fi
}

ensure_key_file_safe() {
  if [[ ! -e "${KEY_PATH}" ]]; then
    die "Service account key not found at ${KEY_PATH}. Place it there or override with GOOGLE_SA_KEY_FILE."
  fi
  if [[ -L "${KEY_PATH}" ]]; then
    die "Service account key must be a regular file, not a symlink: ${KEY_PATH}"
  fi
  if [[ ! -f "${KEY_PATH}" ]]; then
    die "Service account key must be a regular file: ${KEY_PATH}"
  fi
  local mode
  mode=$(get_file_mode "${KEY_PATH}")
  if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
    die "Service account key ${KEY_PATH} must be mode 600 or 400 (current: ${mode}). Run: chmod 600 ${KEY_PATH}"
  fi
}

run_container() {
  docker run --rm \
    --network bridge \
    --read-only --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 256m --cpus 0.5 \
    -v "${KEY_PATH}:/secrets/sa.json:ro" \
    -e GOOGLE_SA_KEY_FILE=/secrets/sa.json \
    -e SPOTIFY_SPREADSHEET_ID \
    "${IMAGE_TAG}" "$@"
}

main() {
  ensure_image_exists
  ensure_spreadsheet_id
  ensure_key_file_safe
  run_container "$@"
}

main "$@"
