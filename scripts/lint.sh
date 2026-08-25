#!/bin/bash
set -euo pipefail

# Repository-wide lint entry point. Linters are grouped by language, not by
# subdirectory, so a file gets the same checks wherever it lives in the
# monorepo. Every job in .github/workflows/lint.yml runs one target of this
# script, so CI and a local run report the same violations.
#
# Usage: scripts/lint.sh [target ...]
# Targets: shell markdown yaml python ansible whitespace (default: all)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# Pinned so a new upstream rule does not turn a green branch red on its own.
readonly MARKDOWNLINT_CLI2_VERSION="0.23.2"

# project-init templates hold placeholders such as PROJECT_DESCRIPTION that
# markdownlint reads as malformed prose.
readonly TEMPLATE_PATH_PREFIX="claude-skills/.claude/skills/project-init/templates/"

readonly ALL_TARGETS="shell markdown yaml python ansible whitespace"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is not installed" >&2
    return 1
  fi
}

list_shell_files() {
  local file
  git ls-files | while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in
      *.sh | *.bash | *.zsh)
        echo "$file"
        continue
        ;;
      # chezmoi's zsh startup files carry neither an extension nor a shebang.
      dotfiles/dot_z*)
        echo "$file"
        continue
        ;;
    esac
    if head -n 1 "$file" | grep -qE '^#!.*[ /](ba|da|k|z)?sh( |$)'; then
      echo "$file"
    fi
  done | sort -u
}

lint_shell() {
  require_command shellcheck
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(list_shell_files)
  shellcheck "${files[@]}"
}

lint_markdown() {
  require_command npx
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files '*.md' | grep -v "^$TEMPLATE_PATH_PREFIX")
  npx --yes "markdownlint-cli2@$MARKDOWNLINT_CLI2_VERSION" "${files[@]}"
}

lint_yaml() {
  require_command yamllint
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files '*.yml' '*.yaml')
  yamllint "${files[@]}"
}

lint_python() {
  require_command ruff
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files '*.py')
  ruff check "${files[@]}"
}

lint_ansible() {
  require_command ansible-lint
  (cd "$REPO_ROOT/ansible" && ansible-lint)
}

lint_whitespace() {
  # -I skips binary files, and git grep never descends into a submodule.
  if git grep -nIE '[[:blank:]]+$' -- .; then
    echo "error: trailing whitespace found" >&2
    return 1
  fi
}

assert_known_target() {
  local target="$1"
  local known
  for known in $ALL_TARGETS; do
    [ "$target" = "$known" ] && return 0
  done
  echo "error: unknown lint target: $target" >&2
  echo "known targets: $ALL_TARGETS" >&2
  return 2
}

main() {
  cd "$REPO_ROOT"
  local targets
  if [ "$#" -eq 0 ]; then
    targets="$ALL_TARGETS"
  else
    targets="$*"
  fi

  local target
  for target in $targets; do
    assert_known_target "$target"
  done

  local exit_status=0
  for target in $targets; do
    echo "==> $target"
    "lint_$target" || exit_status=1
  done
  return "$exit_status"
}

main "$@"
