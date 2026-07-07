#!/usr/bin/env bash
# PostToolUse formatter hook for Claude Code.
#
# Claude Code runs this after every Edit/Write/MultiEdit. It reads the hook
# payload from stdin, extracts the path of the file that was just edited, and
# formats it in place. Every formatter is best-effort: if the tool is missing
# the file is left untouched and the hook still exits 0 so editing is never
# blocked.
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }

payload="$(cat)"

# Pull the edited file path out of the hook JSON (jq preferred, python3 fallback).
file=""
if have jq; then
  file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
elif have python3; then
  file="$(printf '%s' "$payload" |
    python3 -c 'import sys, json; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' 2>/dev/null || true)"
fi

if [ -z "$file" ] || [ ! -f "$file" ]; then
  exit 0
fi

case "$file" in
*.go)
  if have gofmt; then
    gofmt -w -- "$file" >/dev/null 2>&1 || true
  fi
  ;;
*.sh | *.bash)
  if have shfmt; then
    shfmt -i 2 -w -- "$file" >/dev/null 2>&1 || true
  fi
  ;;
esac
