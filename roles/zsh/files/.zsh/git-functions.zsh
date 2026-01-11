# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# Git-related functions

git_delete_all_branched() {
  git branch -D $(git branch --merged | grep -v \* | xargs)
}

function git-branch-remove-all-local() {
  git branch --merged master | grep -v '*' | xargs -I % echo git branch -d %
}

function git-branch-remove-all-local-exec() {
  git branch --merged master | grep -v '*' | xargs -I % git branch -d %
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
  cd ${directory}
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
  cd "${main_repo_root}"

  # Remove the worktree (and directory)
  if git worktree remove "${dir}"; then
    echo "Worktree removed successfully. Exiting shell..."
    exit 0
  else
    echo "Failed to remove worktree."
    # Attempt to go back
    cd "${dir}"
    return 1
  fi
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

function git-commit-llm() {
  # Show help message
  local show_help() {
    cat << EOF
Usage: git-commit-llm [OPTIONS] [MODEL]

Generate a commit message using LLM based on staged changes.

Options:
  -m MODEL    Specify the model to use (default: gemma3:4b)
  -h          Show this help message

Arguments:
  MODEL       Model to use (alternative to -m option)

Examples:
  git-commit-llm                          # Use default model (gemma3:4b)
  git-commit-llm -m gpt-4o                # Use gpt-4o model
  git-commit-llm gpt-4o                   # Use gpt-4o model (positional argument)
  git-commit-llm -h                       # Show help

EOF
  }

  # Check if llm command exists
  if ! command -v llm &> /dev/null; then
    echo "Error: 'llm' command not found. Please install llm (e.g., pip install llm)." >&2
    return 1
  fi

  # Default model and API arguments
  local MODEL_NAME_TO_USE="gemma3:4b"
  local LLM_API_ARGS=(--api ollama) # Default to using Ollama API

  # Parse options
  local OPTIND opt
  while getopts "hm:" opt; do
    case "${opt}" in
      h)
        show_help
        return 0
        ;;
      m)
        MODEL_NAME_TO_USE="${OPTARG}"
        ;;
      *)
        show_help
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  # Check if a model was provided as a positional argument (for backward compatibility)
  if [[ -n "$1" ]]; then
    MODEL_NAME_TO_USE="$1"
  fi

  # Check if there are staged changes
  if ! git diff --staged --quiet; then
    # Get the staged diff
    local DIFF
    DIFF=$(git diff --staged)

    # Use the llm command to generate a commit message
    local SYSTEM_PROMPT="You are a programmer. Based on the Git diff provided below, generate a concise and clear English commit message.
You reply the commit message only.

The first line should be a brief summary (recommended < 50 characters), followed by an empty line, and then a more detailed description from the third line onwards.
Use bullet points in the detailed description of the commit message.

The detailed description should include:
- What changes were made
- Why the changes were made (purpose, background)
- Any impact of the changes (if applicable)
- Use imperative form
"
    local COMMIT_MSG
    # Use the selected model and API arguments
    COMMIT_MSG=$(echo "${DIFF}" | llm -s "${SYSTEM_PROMPT}" -m "${MODEL_NAME_TO_USE}" -m "${MODEL_NAME_TO_USE}")

    # Display the generated message
    echo "--- Generated Commit Message ---"
    echo "$COMMIT_MSG"
    echo "--------------------------------"

    # Ask the user to confirm the commit
    echo -n "Commit with this message? (y/N)"
    local CONFIRM
    read CONFIRM
    if [[ "$CONFIRM" =~ ^[yY]$ ]]; then
      git commit -m "$COMMIT_MSG"
      echo "Committed successfully."
    else
      echo "Commit cancelled."
      # Copy the generated message to the clipboard (macOS)
      # For Linux: echo "$COMMIT_MSG" | xclip -selection clipboard
      echo "$COMMIT_MSG" | pbcopy
      echo "The generated message has been copied to the clipboard."
    fi
  else
    echo "Error: No staged changes found. Please stage your changes with 'git add .' or similar."
  fi
}
