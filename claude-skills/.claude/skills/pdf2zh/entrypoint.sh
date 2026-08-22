#!/bin/sh
# Container entrypoint. Loads the Gemini API key from a read-only mount into
# the environment, then execs pdf2zh with the caller's arguments.

set -eu

if [ ! -f /secrets/gemini.key ]; then
  echo "entrypoint: /secrets/gemini.key not mounted" >&2
  exit 2
fi

GEMINI_API_KEY="$(cat /secrets/gemini.key)"
if [ -z "${GEMINI_API_KEY}" ]; then
  echo "entrypoint: /secrets/gemini.key is empty" >&2
  exit 2
fi
export GEMINI_API_KEY

exec pdf2zh "$@"
