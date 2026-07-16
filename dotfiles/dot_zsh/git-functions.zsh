# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# Git-related functions

git_delete_all_branched() {
  git branch -D $(git branch --merged | grep -v '\*' | xargs)
}

function git-branch-remove-all-local() {
  git branch --merged master | grep -v '\*' | xargs -I % echo git branch -d %
}

function git-branch-remove-all-local-exec() {
  git branch --merged master | grep -v '\*' | xargs -I % git branch -d %
}

function git-branch-remove-all-remote() {
  local remote=$1
  if [ "$remote" = "" ]; then
    echo "Specify remote branch"
  else
    git remote prune $remote
    git branch -a --merged | grep -v master | grep remotes/$remote | sed -e "s% *remotes/$remote/%%" | xargs -I% echo git push $remote :%
  fi
}

function git-branch-remove-all-remote-exec() {
  local remote=$1
  if [ "$remote" = "" ]; then
    echo "Specify remote branch"
  else
    git branch -a --merged | grep -v master | grep remotes/$remote | sed -e "s% *remotes/$remote/%%" | xargs -I% git push $remote :%
  fi
}

function git-worktree-add-with-branch() {
  local directory=$1
  local branch_suffix=$(basename ${directory})
  local date_prefix=$(date +%Y.%m.%d)
  git worktree add "${directory}" -B "${date_prefix}-${branch_suffix}"
  cd "${directory}" || return
}

# Clean up the current worktree: remove the directory, the worktree entry, and exit the shell.
function git-worktree-cleanup-current() {
  local dir=$(pwd)
  # Check if .git is a file (characteristic of a linked worktree root)
  if [ ! -f "${dir}/.git" ]; then
    echo "Error: Current directory is not a linked worktree root (missing .git file)."
    return 1
  fi

  # Find the main repository root
  local common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [ -z "$common_dir" ]; then
    echo "Error: Could not find git common directory."
    return 1
  fi

  # If common_dir is relative, it's relative to the current worktree root.
  # If it's ".git", we are already in the main repo (but the -f .git check above should have caught that).
  local main_repo_root=$(cd "$common_dir/.." && pwd)

  # Go to the main repository root to allow removal of the worktree directory
  cd "${main_repo_root}" || return

  # Remove the worktree (and directory)
  if git worktree remove "${dir}"; then
    echo "Worktree removed successfully. Exiting shell..."
    exit 0
  else
    echo "Failed to remove worktree."
    # Attempt to go back
    cd "${dir}" || return
    return 1
  fi
}

# Interactively select a git worktree by branch name with peco and cd into it.
function git-worktree-select() {
  if ! command -v peco &> /dev/null; then
    echo "Error: 'peco' command not found." >&2
    return 1
  fi

  local worktree_list
  worktree_list=$(git worktree list 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "Error: Not a git repository." >&2
    return 1
  fi

  local worktree_count
  worktree_count=$(echo "$worktree_list" | wc -l | tr -d ' ')
  if [ "$worktree_count" -le 1 ]; then
    echo "No additional worktrees found." >&2
    return 1
  fi

  # Show branch names for selection via peco
  local selected
  selected=$(echo "$worktree_list" | awk '{print $NF}' | tr -d '[]' | peco --prompt "worktree branch>")

  if [ -z "$selected" ]; then
    echo "No worktree selected." >&2
    return 1
  fi

  # Find the directory for the selected branch
  local target_dir
  target_dir=$(echo "$worktree_list" | grep "\[${selected}\]" | awk '{print $1}')

  if [ -z "$target_dir" ]; then
    echo "Error: Could not find worktree for branch '${selected}'." >&2
    return 1
  fi

  echo "Changing to worktree '${selected}' at ${target_dir}"
  cd "$target_dir" || return
}

# Create a git worktree for an open pull request and cd into it.
# Usage:
#   git-worktree-from-pr        # Pick a PR interactively with peco
#   git-worktree-from-pr 123    # Use PR #123 directly
# The worktree is created under <main-repo-root>/.worktrees/pr-<number>.
# `gh pr checkout` runs inside the new worktree, so branch tracking is set up
# correctly even for PRs from forks.
function git-worktree-from-pr() {
  if ! command -v gh &> /dev/null; then
    echo "Error: 'gh' command not found." >&2
    return 1
  fi
  if ! git rev-parse --git-dir &> /dev/null; then
    echo "Error: Not a git repository." >&2
    return 1
  fi

  local pr_number="$1"
  if [ -z "$pr_number" ]; then
    if ! command -v peco &> /dev/null; then
      echo "Error: 'peco' command not found." >&2
      return 1
    fi

    local pr_list
    pr_list=$(gh pr list --limit 100 --json number,headRefName,title \
      --jq '.[] | "#\(.number)\t\(.headRefName)\t\(.title)"')
    if [ -z "$pr_list" ]; then
      echo "No open pull requests found." >&2
      return 1
    fi

    local selected
    selected=$(echo "$pr_list" | peco --prompt "PR>")
    if [ -z "$selected" ]; then
      echo "No PR selected." >&2
      return 1
    fi

    pr_number=$(echo "$selected" | cut -f1 | tr -d '#')
  fi

  # Resolve the main repository root so this also works when invoked from
  # inside another worktree.
  local common_dir
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
  local main_repo_root
  main_repo_root=$(dirname "$common_dir")
  local worktree_dir="${main_repo_root}/.worktrees/pr-${pr_number}"

  if [ -d "$worktree_dir" ]; then
    echo "Worktree directory already exists: ${worktree_dir}"
    cd "$worktree_dir" || return
    return 0
  fi

  # Create a detached worktree first, then let gh check out the PR branch.
  git worktree add --detach "$worktree_dir" || return
  cd "$worktree_dir" || return
  gh pr checkout "$pr_number"
}

function git-branch-for-pr() {
  CURRENT_BRANCH_NAME=$(git branch --show-current)
  ORIGINAL_BRANCH=$(git remote show origin | sed -n '/HEAD branch/s/.*: //p')

  git checkout "${ORIGINAL_BRANCH}"
  git pull
  echo "Creating a branch pr/${CURRENT_BRANCH_NAME}"
  git checkout -b "pr/${CURRENT_BRANCH_NAME}"
  git cherry-pick "${CURRENT_BRANCH_NAME}"
  git push -u garaemon "pr/${CURRENT_BRANCH_NAME}"
  git checkout "${CURRENT_BRANCH_NAME}"
}

# Convert GitHub HTTP URL to SSH URL
# Usage:
#   github-http-to-ssh https://github.com/user/repo.git
#   github-http-to-ssh origin  # Convert the specified remote URL
#   github-http-to-ssh         # Convert origin remote URL
function github-http-to-ssh() {
  local input="${1:-origin}"
  local url=""

  # Check if input is a URL or a remote name
  if [[ "$input" =~ ^https?:// ]]; then
    # Input is a URL
    url="$input"
  else
    # Input is a remote name, get its URL
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
      echo "Error: Not a git repository"
      return 1
    fi

    url=$(git remote get-url "$input" 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "Error: Remote '$input' not found"
      return 1
    fi
  fi

  # Convert HTTP/HTTPS URL to SSH format
  if [[ "$url" =~ ^https?://github\.com/ ]]; then
    # Extract user and repo from URL
    # Handles both https://github.com/user/repo.git and https://github.com/user/repo
    local ssh_url=$(echo "$url" | sed -E 's|^https?://github\.com/|git@github.com:|')

    # If input was a remote name, update it
    if [[ ! "$input" =~ ^https?:// ]]; then
      echo "Converting remote '$input' from:"
      echo "  $url"
      echo "to:"
      echo "  $ssh_url"
      git remote set-url "$input" "$ssh_url"
      echo "Remote '$input' updated successfully"
    else
      # Just output the converted URL
      echo "$ssh_url"
    fi
  else
    if [[ "$url" =~ ^git@github\.com: ]]; then
      echo "URL is already in SSH format: $url"
    else
      echo "Error: Not a GitHub HTTP/HTTPS URL: $url"
      return 1
    fi
  fi
}

# git-commit-llm is now a standalone Python script at ~/.local/bin/git-commit-llm
