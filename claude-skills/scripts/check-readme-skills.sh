#!/usr/bin/env bash
# Verify that README.md links to every skill under .claude/skills/.
# A skill is any directory under .claude/skills/ that contains SKILL.md.
# Each such skill must appear in README.md as a link to its SKILL.md path.

set -euo pipefail

readme_path="README.md"
skills_root=".claude/skills"

if [ ! -f "$readme_path" ]; then
  echo "error: $readme_path not found" >&2
  exit 1
fi

if [ ! -d "$skills_root" ]; then
  echo "No skills directory found; nothing to check."
  exit 0
fi

shopt -s nullglob
missing=()
found_any=0
for skill_dir in "$skills_root"/*/; do
  skill_name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  if [ ! -f "$skill_md" ]; then
    continue
  fi
  found_any=1
  expected_link="$skills_root/$skill_name/SKILL.md"
  if ! grep -qF "$expected_link" "$readme_path"; then
    missing+=("$skill_name")
  fi
done

if [ "$found_any" -eq 0 ]; then
  echo "No skills with SKILL.md found; nothing to check."
  exit 0
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "README.md is missing links for the following skills:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "" >&2
  echo "Each skill under $skills_root/<name>/SKILL.md must be linked from $readme_path" >&2
  echo "using its path, e.g. [<name>]($skills_root/<name>/SKILL.md)." >&2
  exit 1
fi

echo "All skills are linked in $readme_path."
