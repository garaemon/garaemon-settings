#!/bin/bash
set -euo pipefail

# Upload Markdown reports (and the images they show) as one GitHub gist on the
# host that the current repository's origin remote points at, and print the
# gist URL.
#
# Usage: post-gist.sh [--public] [--description TEXT] FILE.md [FILE.md ...] [IMAGE ...]
#
# Image links in the Markdown files may use any relative path that ends in the
# image's file name. They are rewritten to the gist's raw URL.

readonly IMAGE_EXTENSIONS='png jpg jpeg gif svg webp'
# Image names go into a sed expression, so allow only characters that are
# literal there and safe in a URL.
# Use gh as the only credential helper so a clone or push on GitHub Enterprise
# authenticates without a terminal prompt.
readonly GH_CREDENTIAL_OPTIONS=(-c credential.helper= -c "credential.helper=!gh auth git-credential")
readonly SAFE_FILE_NAME_PATTERN='^[A-Za-z0-9_-][A-Za-z0-9._-]*$'

usage() {
  echo "Usage: $(basename "$0") [--public] [--description TEXT] FILE.md [FILE.md ...] [IMAGE ...]" >&2
}

# Print the hostname of a git remote URL. Handles https://, ssh://, and the
# scp-like shorthand (git@host:owner/repo). Prints nothing for a local path.
parse_host_from_remote_url() {
  local url="$1"
  local authority
  case "$url" in
    *://*)
      authority="${url#*://}"
      authority="${authority%%/*}"
      authority="${authority##*@}"
      echo "${authority%%:*}"
      ;;
    *@*:*)
      authority="${url#*@}"
      echo "${authority%%:*}"
      ;;
  esac
}

detect_origin_host() {
  local origin_url host
  origin_url="$(git remote get-url origin 2>/dev/null)" || {
    echo "error: no 'origin' remote in $(pwd)" >&2
    return 1
  }
  host="$(parse_host_from_remote_url "$origin_url")"
  if [ -z "$host" ]; then
    echo "error: cannot find a host in origin URL: ${origin_url}" >&2
    return 1
  fi
  echo "$host"
}

is_image_file() {
  case "$1" in
    *.png | *.jpg | *.jpeg | *.gif | *.svg | *.webp) return 0 ;;
    *) return 1 ;;
  esac
}

# Fail when two files would land under the same name in the flat gist.
assert_unique_base_names() {
  local label="$1"
  shift
  local file_path duplicate
  duplicate="$(for file_path in "$@"; do echo "${file_path##*/}"; done | sort | uniq -d | head -n1)"
  if [ -n "$duplicate" ]; then
    echo "error: two ${label} files share the name '${duplicate}'; a gist is flat" >&2
    return 1
  fi
}

assert_safe_image_names() {
  local image_path image_name
  for image_path in "$@"; do
    image_name="$(basename "$image_path")"
    if ! [[ "$image_name" =~ $SAFE_FILE_NAME_PATTERN ]]; then
      echo "error: unsafe image file name '${image_name}'; use letters, digits, '.', '_' and '-'" >&2
      return 1
    fi
  done
}

# Rewrite links that end in IMAGE_NAME inside MARKDOWN_FILE to RAW_URL.
# Matches Markdown links "](path/name.png)" and HTML attributes src="path/name.png".
rewrite_image_links() {
  local markdown_file="$1"
  local image_name="$2"
  local raw_url="$3"
  local escaped_name="${image_name//./\\.}"
  local temporary_file="${markdown_file}.rewrite"
  sed -E "s#(\]\(|src=\")([^)\" ]*/)?${escaped_name}(\)|\")#\1${raw_url}\3#g" \
    "$markdown_file" >"$temporary_file"
  mv "$temporary_file" "$markdown_file"
}

# Clone the gist into CLONE_DIRECTORY, add the images, point the Markdown links
# at the raw URLs, and push. gh gist create cannot upload binary files, but the
# gist is a git repository that accepts them.
#
# Usage: push_images_to_gist CLONE_DIRECTORY GIST_URL MARKDOWN_COUNT MARKDOWN_NAME... IMAGE_PATH...
# MARKDOWN_NAME is a base name inside the gist; IMAGE_PATH is a local path.
push_images_to_gist() {
  local clone_directory="$1"
  local gist_url="$2"
  local markdown_count="$3"
  shift 3
  local markdown_names=("${@:1:markdown_count}")
  shift "$markdown_count"
  local image_paths=("$@")

  git "${GH_CREDENTIAL_OPTIONS[@]}" clone -q "${gist_url}.git" "${clone_directory}/gist"
  local image_path image_name markdown_name
  for image_path in "${image_paths[@]}"; do
    image_name="$(basename "$image_path")"
    cp "$image_path" "${clone_directory}/gist/${image_name}"
    for markdown_name in "${markdown_names[@]}"; do
      rewrite_image_links "${clone_directory}/gist/${markdown_name}" \
        "$image_name" "${gist_url}/raw/${image_name}"
    done
  done

  local author_name author_email
  author_name="$(git config user.name || echo gist-report)"
  author_email="$(git config user.email || echo gist-report@users.noreply.github.com)"
  git -C "${clone_directory}/gist" add -A
  git -C "${clone_directory}/gist" \
    -c "user.name=${author_name}" -c "user.email=${author_email}" \
    commit -q -m "Add images"
  git -C "${clone_directory}/gist" "${GH_CREDENTIAL_OPTIONS[@]}" push -q origin HEAD
}

main() {
  local is_public="false"
  local description=""
  local markdown_paths=()
  local image_paths=()
  local argument_path

  while [ $# -gt 0 ]; do
    case "$1" in
      --public)
        is_public="true"
        shift
        ;;
      --description)
        [ $# -ge 2 ] || { usage; return 2; }
        description="$2"
        shift 2
        ;;
      -*)
        usage
        return 2
        ;;
      *)
        argument_path="$1"
        if [ ! -f "$argument_path" ]; then
          echo "error: file not found: ${argument_path}" >&2
          return 1
        fi
        if [[ "$argument_path" == *.md ]]; then
          markdown_paths+=("$argument_path")
        elif is_image_file "$argument_path"; then
          image_paths+=("$argument_path")
        else
          echo "error: only .md files and images (${IMAGE_EXTENSIONS}) are supported: ${argument_path}" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  if [ "${#markdown_paths[@]}" -eq 0 ]; then
    usage
    return 2
  fi
  assert_unique_base_names Markdown "${markdown_paths[@]}"
  if [ "${#image_paths[@]}" -gt 0 ]; then
    assert_unique_base_names image "${image_paths[@]}"
    assert_safe_image_names "${image_paths[@]}"
  fi

  local host
  host="$(detect_origin_host)"

  # Export for every gh and git call below. An inherited GH_HOST is replaced
  # because the repository decides which server to use.
  export GH_HOST="$host"

  local gh_arguments=(gist create)
  if [ "$is_public" = "true" ]; then
    gh_arguments+=(--public)
  fi
  if [ -n "$description" ]; then
    gh_arguments+=(-d "$description")
  fi
  gh_arguments+=("${markdown_paths[@]}")

  local gist_url
  gist_url="$(gh "${gh_arguments[@]}" | tail -n1)"

  if [ "${#image_paths[@]}" -gt 0 ]; then
    local markdown_names=()
    local markdown_path
    for markdown_path in "${markdown_paths[@]}"; do
      markdown_names+=("$(basename "$markdown_path")")
    done
    # EXIT, not RETURN: set -e leaves the script without returning from the
    # function, so a RETURN trap would not remove the clone.
    local clone_directory
    clone_directory="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${clone_directory}'" EXIT
    echo "created ${gist_url}; uploading images (on failure: gh gist delete ${gist_url##*/})" >&2
    push_images_to_gist "$clone_directory" "$gist_url" "${#markdown_names[@]}" \
      "${markdown_names[@]}" "${image_paths[@]}"
  fi
  echo "$gist_url"
}

main "$@"
