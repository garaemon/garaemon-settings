#!/usr/bin/env bash
# PostToolUse formatter hook for Claude Code.
#
# Claude Code runs this after every Edit/Write/MultiEdit. It reads the hook
# payload from stdin, finds the file that was just edited, and formats it in
# place based on its extension.
#
# One script serves every project the project-init skill scaffolds (it is
# copied from templates/common), so it carries a branch for each supported
# language. Branches whose tools are absent in a given project simply no-op.
#
# Every formatter is best-effort: a missing tool leaves the file untouched and
# the hook still exits 0, so editing is never blocked. Project-local tools are
# preferred over globally installed ones so a project's pinned versions win.
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
# Run a formatter, discarding its output and never failing the hook.
run() { "$@" >/dev/null 2>&1 || true; }

root="${CLAUDE_PROJECT_DIR:-.}"

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
*.py)
  # Prefer the project virtualenv's ruff, then uv (which resolves it), then a
  # global ruff. Apply safe lint fixes (import sorting, ...) then format;
  # --fix-only never reports leftover violations, so it can't become noise.
  if [ -x "$root/.venv/bin/ruff" ]; then
    run "$root/.venv/bin/ruff" check --fix-only -- "$file"
    run "$root/.venv/bin/ruff" format -- "$file"
  elif have uv; then
    run uv run --quiet ruff check --fix-only -- "$file"
    run uv run --quiet ruff format -- "$file"
  elif have ruff; then
    run ruff check --fix-only -- "$file"
    run ruff format -- "$file"
  fi
  ;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.md | *.yaml | *.yml)
  # Prefer the project-local prettier, then npx (also local-resolving), then a
  # global prettier.
  if [ -x "$root/node_modules/.bin/prettier" ]; then
    run "$root/node_modules/.bin/prettier" --write -- "$file"
  elif have npx; then
    run npx --no-install prettier --write -- "$file"
  elif have prettier; then
    run prettier --write -- "$file"
  fi
  ;;
*.go)
  if have gofmt; then
    run gofmt -w -- "$file"
  fi
  ;;
*.sh | *.bash)
  if have shfmt; then
    run shfmt -i 2 -w -- "$file"
  fi
  ;;
esac
