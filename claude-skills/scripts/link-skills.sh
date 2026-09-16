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

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills" && pwd)"
readonly SOURCE_DIR

# Symlinks one skill directory into "$target_dir". Returns non-zero when the
# name is taken by anything this script did not create: a managed container
# installs its own skills, and one sharing a name with a skill here has to
# survive the run, whether it sits there as a directory or as a symlink of the
# platform's own.
link_skill() {
  local skill_path="$1"
  local target_dir="$2"
  local skill_name link_path current_target
  skill_name="$(basename "$skill_path")"
  link_path="$target_dir/$skill_name"

  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    current_target="$(readlink "$link_path" || true)"
    case "$current_target" in
      "$SOURCE_DIR"/*) ;;
      *)
        printf 'skipped %s: %s is not a link into this repository\n' \
          "$skill_name" "$link_path" >&2
        return 1
        ;;
    esac
  fi

  # main calls this from an `if`, which switches `set -e` off for the whole
  # body, so a failing ln has to be caught here or the skill counts as linked.
  if ! ln -sfn "$skill_path" "$link_path"; then
    printf 'failed to link %s into %s\n' "$skill_name" "$target_dir" >&2
    return 1
  fi
  printf 'linked %s\n' "$skill_name"
}

# Removes the links this script left behind for skills that no longer exist,
# which a rename or a branch switch leaves dangling. Only links into this
# repository are considered, so nothing the platform installed is touched.
remove_stale_links() {
  local target_dir="$1"
  local link_path current_target
  for link_path in "$target_dir"/*; do
    [ -L "$link_path" ] || continue
    current_target="$(readlink "$link_path")"
    case "$current_target" in
      "$SOURCE_DIR"/*) ;;
      *) continue ;;
    esac
    if [ ! -f "$current_target/SKILL.md" ]; then
      rm "$link_path"
      printf 'removed %s, which no longer names a skill\n' "$(basename "$link_path")"
    fi
  done
}

main() {
  local target_dir="${1:-$HOME/.claude/skills}"
  mkdir -p "$target_dir"
  remove_stale_links "$target_dir"

  local skill_path linked_count=0 skipped_count=0
  for skill_path in "$SOURCE_DIR"/*; do
    [ -f "$skill_path/SKILL.md" ] || continue
    if link_skill "$skill_path" "$target_dir"; then
      linked_count=$((linked_count + 1))
    else
      skipped_count=$((skipped_count + 1))
    fi
  done

  printf '%d skills linked, %d skipped\n' "$linked_count" "$skipped_count"
  # A setup script runs this unattended, where nobody reads the skipped lines
  # above. Fail so that a container holding none of these skills is not
  # reported as a successful setup.
  if [ "$linked_count" -eq 0 ]; then
    printf 'no skill was linked into %s\n' "$target_dir" >&2
    return 1
  fi
}

main "$@"
