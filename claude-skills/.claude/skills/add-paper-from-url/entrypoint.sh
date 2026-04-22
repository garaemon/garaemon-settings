#!/bin/sh
# Container entrypoint for the add-paper-from-url skill. Exposes two
# subcommands: `paperpile` (proxy to the Paperpile CLI) and `fetch` (a
# locked-down wrapper around curl that writes into the mounted workspace).

set -eu

WORKSPACE_DIR="/tmp/paperpile-add"

usage() {
  cat >&2 <<EOF
Usage: entrypoint.sh <subcommand> [args...]

Subcommands:
  paperpile <args...>       Run the Paperpile CLI with the given arguments.
  fetch <url> <output-path> Download a PDF from <url> to <output-path>.
                            The output path must be under ${WORKSPACE_DIR}/.
  help                      Print this message.
EOF
}

fail() {
  echo "entrypoint.sh: error: $*" >&2
  exit 2
}

run_fetch() {
  if [ "$#" -ne 2 ]; then
    fail "fetch: expected <url> <output-path>, got $# args"
  fi
  fetch_url="$1"
  fetch_out="$2"
  case "$fetch_out" in
    "${WORKSPACE_DIR}"/*) ;;
    *) fail "fetch: output-path must be under ${WORKSPACE_DIR}/ (got: ${fetch_out})" ;;
  esac
  # Reject '..' components so a traversal like /tmp/paperpile-add/../evil.pdf
  # cannot escape the workspace and land in the container's tmpfs root.
  case "$fetch_out" in
    *..*) fail "fetch: output-path must not contain '..' components: ${fetch_out}" ;;
  esac
  # Restrict curl to http(s) on both the initial request and redirects. Without
  # this, a malicious redirect to file:// could exfiltrate the mounted Paperpile
  # config or other container-local files.
  # OpenReview (and some other publishers) reject requests that lack a browser-like
  # User-Agent with HTTP 403, so advertise one explicitly.
  exec curl -sS -L -f --max-time 60 \
    --proto '=https,http' \
    --proto-redir '=https,http' \
    -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36' \
    -o "$fetch_out" "$fetch_url"
}

main() {
  if [ "$#" -eq 0 ]; then
    usage
    exit 2
  fi
  subcmd="$1"
  shift
  case "$subcmd" in
    paperpile)
      exec paperpile "$@"
      ;;
    fetch)
      run_fetch "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "entrypoint.sh: unknown subcommand: ${subcmd}" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
