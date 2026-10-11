#!/bin/bash
set -euo pipefail

# Upload a Markdown report as a GitHub gist on the host that the current
# repository's origin remote points at, and print the gist URL.
#
# Usage: post-gist.sh [--public] [--description TEXT] REPORT.md

usage() {
  echo "Usage: $(basename "$0") [--public] [--description TEXT] REPORT.md" >&2
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

main() {
  local is_public="false"
  local description=""
  local report_file=""

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
        [ -z "$report_file" ] || { usage; return 2; }
        report_file="$1"
        shift
        ;;
    esac
  done

  if [ -z "$report_file" ]; then
    usage
    return 2
  fi
  if [ ! -f "$report_file" ]; then
    echo "error: file not found: ${report_file}" >&2
    return 1
  fi
  if [[ "$report_file" != *.md ]]; then
    echo "error: report must be a .md file so the gist renders as Markdown: ${report_file}" >&2
    return 1
  fi

  local host
  host="$(detect_origin_host)"

  # Override any inherited GH_HOST: the repository decides which server to use.
  local gh_arguments=(gist create)
  if [ "$is_public" = "true" ]; then
    gh_arguments+=(--public)
  fi
  if [ -n "$description" ]; then
    gh_arguments+=(-d "$description")
  fi
  gh_arguments+=("$report_file")

  GH_HOST="$host" gh "${gh_arguments[@]}"
}

main "$@"
