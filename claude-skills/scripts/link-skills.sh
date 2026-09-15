#!/bin/bash
set -euo pipefail

# Links every skill of this repository into a Claude Code personal skills
# directory, one symlink per skill.
#
# A workstation instead points the whole ~/.claude/skills directory at this
# repository (see ../README.md). A managed container such as Claude Code on
# the web cannot do that, because the platform already installs its own
# skills there. Per-skill symlinks add these skills beside those.
#
# Usage: link-skills.sh [target-directory]   (default: ~/.claude/skills)

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.claude/skills" && pwd)"
readonly SOURCE_DIR

# Symlinks one skill directory into "$target_dir" unless the name is taken by
# something this script did not create.
link_skill() {
  local skill_path="$1"
  local target_dir="$2"
  local skill_name link_path
  skill_name="$(basename "$skill_path")"
  link_path="$target_dir/$skill_name"

  if [ ! -f "$skill_path/SKILL.md" ]; then
    return 0
  fi
  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    printf 'skipped %s: %s exists and is not a symlink\n' \
      "$skill_name" "$link_path" >&2
    return 0
  fi

  ln -sfn "$skill_path" "$link_path"
  printf 'linked %s\n' "$skill_name"
}

main() {
  local target_dir="${1:-$HOME/.claude/skills}"
  mkdir -p "$target_dir"

  local skill_path
  for skill_path in "$SOURCE_DIR"/*; do
    link_skill "$skill_path" "$target_dir"
  done
}

main "$@"
