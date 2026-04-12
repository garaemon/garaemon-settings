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
  cd "$target_dir"
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
  -f FEEDBACK Provide feedback/instructions for commit message generation
  -h          Show this help message

Arguments:
  MODEL       Model to use (alternative to -m option)

Interactive commands after message generation:
  y - Commit with the displayed message
  e - Open message in \$EDITOR for manual editing
  f - Provide feedback and regenerate the message with LLM
  n - Cancel commit (copies message to clipboard)

Examples:
  git-commit-llm                                       # Use default model
  git-commit-llm -m gpt-4o                             # Use gpt-4o model
  git-commit-llm -f "focus on the API changes"         # Provide initial feedback
  git-commit-llm -m gpt-4o -f "write in Japanese"      # Combine options
  git-commit-llm gpt-4o                                # Positional model argument
  git-commit-llm -h                                    # Show help

EOF
  }

  # Format JSON response into a commit message string
  # Input: JSON string with "summary" and "details" fields
  # Output: formatted commit message (summary + blank line + bullet points)
  local _format_commit_json() {
    local raw_json="$1"
    # Strip markdown code fences if the LLM wraps the response
    local json
    json=$(echo "$raw_json" | sed '/^```\(json\)\{0,1\}$/d')

    local summary
    summary=$(echo "$json" | jq -r '.summary // empty' 2>/dev/null)

    if [[ -z "$summary" ]]; then
      # Fallback: if JSON parsing fails, return raw text as-is
      echo "$raw_json"
      return 1
    fi

    # Strip leading/trailing whitespace and newlines from summary
    summary=$(echo "$summary" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')

    # Format details: strip whitespace from each item, prefix with "- "
    local details=""
    local detail_lines
    detail_lines=$(echo "$json" | jq -r '.details[]?' 2>/dev/null)
    if [[ -n "$detail_lines" ]]; then
      while IFS= read -r line; do
        # Strip leading/trailing whitespace and newlines from each detail
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')
        if [[ -n "$line" ]]; then
          if [[ -n "$details" ]]; then
            details="${details}"$'\n'"- ${line}"
          else
            details="- ${line}"
          fi
        fi
      done <<< "$detail_lines"
    fi

    if [[ -n "$details" ]]; then
      printf '%s\n\n%s\n' "$summary" "$details"
    else
      echo "$summary"
    fi
  }

  # Check if llm command exists
  if ! command -v llm &> /dev/null; then
    echo "Error: 'llm' command not found. Please install llm (e.g., pip install llm)." >&2
    return 1
  fi

  # Check if jq command exists
  if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' command not found. Please install jq." >&2
    return 1
  fi

  # Default model and API arguments
  local MODEL_NAME_TO_USE="gemma3:4b"
  local LLM_API_ARGS=(--api ollama) # Default to using Ollama API
  local INITIAL_FEEDBACK=""

  # Parse options
  local OPTIND opt
  while getopts "hm:f:" opt; do
    case "${opt}" in
      h)
        show_help
        return 0
        ;;
      m)
        MODEL_NAME_TO_USE="${OPTARG}"
        ;;
      f)
        INITIAL_FEEDBACK="${OPTARG}"
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

    # Base system prompt - asks LLM to return structured JSON
    local BASE_SYSTEM_PROMPT='You are a programmer. Based on the Git diff provided below, generate a concise and clear commit message.
Reply ONLY with a JSON object (no markdown code fences, no extra text).

JSON schema:
{
  "summary": "brief summary in imperative form (< 50 characters)",
  "details": [
    "bullet point describing what was changed",
    "bullet point describing why (purpose/background)",
    "bullet point describing impact (if applicable)"
  ]
}

Rules:
- "summary" must be a single line, imperative form, under 50 characters
- "details" is an array of strings, each describing one aspect of the change in imperative form
- Do NOT wrap the JSON in markdown code fences or any other formatting
- Reply with the JSON object only, nothing else
'

    # Build system prompt with optional initial feedback
    local SYSTEM_PROMPT="${BASE_SYSTEM_PROMPT}"
    if [[ -n "${INITIAL_FEEDBACK}" ]]; then
      SYSTEM_PROMPT="${SYSTEM_PROMPT}
Additional instructions from the user:
${INITIAL_FEEDBACK}
"
    fi

    local LLM_RAW COMMIT_MSG
    # Use the selected model to generate the commit message
    LLM_RAW=$(echo "${DIFF}" | llm -s "${SYSTEM_PROMPT}" -m "${MODEL_NAME_TO_USE}")
    COMMIT_MSG=$(_format_commit_json "$LLM_RAW")

    # Interactive loop: show message and prompt for action
    while true; do
      echo "--- Generated Commit Message ---"
      echo "$COMMIT_MSG"
      echo "--------------------------------"

      echo -n "(y)es / (e)dit / (f)eedback / (n)o: "
      local CONFIRM
      read CONFIRM
      case "$CONFIRM" in
        [yY])
          git commit -m "$COMMIT_MSG"
          echo "Committed successfully."
          return 0
          ;;
        [eE])
          # Open in editor for manual adjustment
          local TMPFILE
          TMPFILE=$(mktemp "${TMPDIR:-/tmp}/git-commit-llm.XXXXXX")
          echo "$COMMIT_MSG" > "$TMPFILE"
          "${EDITOR:-vi}" "$TMPFILE"
          COMMIT_MSG=$(<"$TMPFILE")
          rm -f "$TMPFILE"
          if [[ -z "${COMMIT_MSG// /}" ]]; then
            echo "Commit message is empty. Aborting."
            return 1
          fi
          # Loop back to show the edited message
          ;;
        [fF])
          # Ask for feedback and regenerate
          echo -n "Feedback: "
          local FEEDBACK
          read FEEDBACK
          if [[ -z "${FEEDBACK}" ]]; then
            echo "No feedback provided. Keeping current message."
            continue
          fi
          local FEEDBACK_PROMPT="${BASE_SYSTEM_PROMPT}
The following commit message was previously generated but the user wants it revised:
---
${COMMIT_MSG}
---

User's feedback for revision:
${FEEDBACK}
"
          echo "Regenerating commit message..."
          LLM_RAW=$(echo "${DIFF}" | llm -s "${FEEDBACK_PROMPT}" -m "${MODEL_NAME_TO_USE}")
          COMMIT_MSG=$(_format_commit_json "$LLM_RAW")
          # Loop back to show the new message
          ;;
        *)
          echo "Commit cancelled."
          # Copy to clipboard (try macOS first, then Linux)
          if command -v pbcopy &> /dev/null; then
            echo "$COMMIT_MSG" | pbcopy
            echo "The generated message has been copied to the clipboard."
          elif command -v xclip &> /dev/null; then
            echo "$COMMIT_MSG" | xclip -selection clipboard
            echo "The generated message has been copied to the clipboard."
          fi
          return 0
          ;;
      esac
    done
  else
    echo "Error: No staged changes found. Please stage your changes with 'git add .' or similar."
  fi
}
