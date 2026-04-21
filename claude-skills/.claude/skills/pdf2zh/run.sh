#!/usr/bin/env bash
# Wrapper that runs the pdf2zh CLI inside a hardened Docker container.
# Mounts the input PDF and Gemini API key read-only and the output dir
# read-write, then passes all translation-related args through to pdf2zh.

set -euo pipefail

readonly IMAGE_TAG="pdf2zh:local"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_KEY_PATH="${HOME}/.config/pdf2zh/gemini.key"
readonly KEY_PATH="${GEMINI_KEY_FILE:-${DEFAULT_KEY_PATH}}"
readonly DEFAULT_OUTPUT_DIR="/tmp/pdf2zh"
readonly DEFAULT_SOURCE_LANG="en"
readonly DEFAULT_TARGET_LANG="ja"
readonly DEFAULT_MODEL="${PDF2ZH_GEMINI_MODEL:-gemini-3-flash-preview}"

die() {
  echo "run.sh: error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: run.sh <input.pdf> [--output DIR] [--source-lang LANG]
                          [--target-lang LANG] [--model MODEL]
                          [--pages RANGE] [-- <extra pdf2zh args>]

Translate a PDF with pdf2zh (PDFMathTranslate) using Gemini. Outputs
<basename>-mono.pdf and <basename>-dual.pdf under the output directory.
EOF
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

ensure_key_file_safe() {
  if [[ ! -e "${KEY_PATH}" ]]; then
    die "Gemini API key not found at ${KEY_PATH}. Place it there or override with GEMINI_KEY_FILE."
  fi
  if [[ -L "${KEY_PATH}" ]]; then
    die "Gemini API key must be a regular file, not a symlink: ${KEY_PATH}"
  fi
  if [[ ! -f "${KEY_PATH}" ]]; then
    die "Gemini API key must be a regular file: ${KEY_PATH}"
  fi
  local mode
  mode=$(get_file_mode "${KEY_PATH}")
  if [[ "${mode}" != "600" && "${mode}" != "400" ]]; then
    die "Gemini API key ${KEY_PATH} must be mode 600 or 400 (current: ${mode}). Run: chmod 600 ${KEY_PATH}"
  fi
}

resolve_abs_path() {
  local target="$1"
  local dir
  local base
  dir=$(cd "$(dirname "${target}")" && pwd)
  base=$(basename "${target}")
  printf '%s/%s\n' "${dir}" "${base}"
}

parse_args() {
  INPUT_PDF=""
  OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
  SOURCE_LANG="${DEFAULT_SOURCE_LANG}"
  TARGET_LANG="${DEFAULT_TARGET_LANG}"
  MODEL="${DEFAULT_MODEL}"
  PAGES=""
  EXTRA_ARGS=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --output)
        [[ $# -ge 2 ]] || die "--output requires a value"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --source-lang)
        [[ $# -ge 2 ]] || die "--source-lang requires a value"
        SOURCE_LANG="$2"
        shift 2
        ;;
      --target-lang)
        [[ $# -ge 2 ]] || die "--target-lang requires a value"
        TARGET_LANG="$2"
        shift 2
        ;;
      --model)
        [[ $# -ge 2 ]] || die "--model requires a value"
        MODEL="$2"
        shift 2
        ;;
      --pages)
        [[ $# -ge 2 ]] || die "--pages requires a value"
        PAGES="$2"
        shift 2
        ;;
      --)
        shift
        EXTRA_ARGS+=("$@")
        break
        ;;
      -*)
        die "unknown flag: $1 (use '--' to pass flags through to pdf2zh)"
        ;;
      *)
        if [[ -n "${INPUT_PDF}" ]]; then
          die "only one input PDF is supported; got '${INPUT_PDF}' and '$1'"
        fi
        INPUT_PDF="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${INPUT_PDF}" ]]; then
    usage
    exit 2
  fi
}

ensure_input_pdf() {
  if [[ ! -e "${INPUT_PDF}" ]]; then
    die "input PDF not found: ${INPUT_PDF}"
  fi
  if [[ -L "${INPUT_PDF}" ]]; then
    die "input PDF must be a regular file, not a symlink: ${INPUT_PDF}"
  fi
  if [[ ! -f "${INPUT_PDF}" ]]; then
    die "input PDF must be a regular file: ${INPUT_PDF}"
  fi
  if [[ "${INPUT_PDF}" != *.pdf && "${INPUT_PDF}" != *.PDF ]]; then
    die "input file does not have a .pdf extension: ${INPUT_PDF}"
  fi
}

ensure_output_dir() {
  mkdir -p "${OUTPUT_DIR}"
  if [[ ! -d "${OUTPUT_DIR}" ]]; then
    die "output path exists but is not a directory: ${OUTPUT_DIR}"
  fi
}

run_container() {
  local input_abs
  local output_abs
  local basename
  input_abs=$(resolve_abs_path "${INPUT_PDF}")
  output_abs=$(resolve_abs_path "${OUTPUT_DIR}")
  basename=$(basename "${INPUT_PDF}")

  local pdf2zh_args=(
    "/input/${basename}"
    -s "gemini:${MODEL}"
    -li "${SOURCE_LANG}"
    -lo "${TARGET_LANG}"
  )
  if [[ -n "${PAGES}" ]]; then
    pdf2zh_args+=(-p "${PAGES}")
  fi
  if (( ${#EXTRA_ARGS[@]} > 0 )); then
    pdf2zh_args+=("${EXTRA_ARGS[@]}")
  fi

  docker run --rm \
    --network bridge \
    --read-only --tmpfs /tmp \
    --cap-drop ALL \
    --security-opt no-new-privileges \
    --memory 2g --cpus 1.0 \
    -w /output \
    -v "${input_abs}:/input/${basename}:ro" \
    -v "${output_abs}:/output" \
    -v "${KEY_PATH}:/secrets/gemini.key:ro" \
    "${IMAGE_TAG}" "${pdf2zh_args[@]}"
}

main() {
  parse_args "$@"
  ensure_image_exists
  ensure_key_file_safe
  ensure_input_pdf
  ensure_output_dir
  run_container
}

main "$@"
