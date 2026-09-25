#!/bin/bash
set -euo pipefail

# One-shot setup for a fresh machine. Run it without cloning anything first:
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/garaemon/garaemon-settings/main/bootstrap.sh)"
#
# Use `bash -c "$(curl ...)"` rather than `curl ... | bash`. A pipe takes over
# stdin, so the sudo and Ansible become password prompts would read the script
# instead of the keyboard.
#
# The script needs neither ghq nor Ansible beforehand; it installs both. It
# stays compatible with bash 3.2 because macOS runs it with the system bash
# before Homebrew has installed a newer one.

readonly REPOSITORY_URL="https://github.com/garaemon/garaemon-settings.git"
readonly ALLOWED_PLAYBOOKS="main minimal ax8-max"
# ~/.emacs.d and ~/.claude/skills are chezmoi symlinks that point at this exact
# path, so the checkout cannot live anywhere else.
readonly CHECKOUT_DIR="${HOME}/ghq/github.com/garaemon/garaemon-settings"
readonly CHEZMOI_SOURCE_DIR_LINE='sourceDir = "~/ghq/github.com/garaemon/garaemon-settings"'
readonly ANSIBLE_VENV_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/garaemon-settings/ansible-venv"

log() {
    printf '[bootstrap] %s\n' "$*"
}

warn() {
    printf '[bootstrap] ERROR: %s\n' "$*" >&2
}

# Succeeds when run_as_root can work: the user is root, or sudo is installed.
# A sudo that asks for a password still counts, because the prompt can succeed.
has_root_access() {
    [[ "${EUID}" -eq 0 ]] || command -v sudo >/dev/null 2>&1
}

# Runs a command as root, directly when already root (e.g. in a container
# without sudo) and through sudo otherwise.
run_as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Puts brew on PATH for this process. A fresh Homebrew install on Apple
# silicon lives in /opt/homebrew, which the login shell does not know yet.
activate_homebrew() {
    local brew_path
    for brew_path in "$(command -v brew || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -n "${brew_path}" && -x "${brew_path}" ]]; then
            eval "$("${brew_path}" shellenv)"
            return 0
        fi
    done
    return 1
}

# Usage: install_debian_prerequisites <has_root> <needs_python> <needs_venv>
# Ansible needs python3 and its venv module, and build_emacs.py needs python3
# alone. Without root the function cannot install anything, so it exits when
# a package is missing.
install_debian_prerequisites() {
    local has_root="$1"
    local needs_python="$2"
    local needs_venv="$3"
    local -a missing_packages=()
    command -v git >/dev/null 2>&1 || missing_packages+=(git)
    command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
    if [[ "${needs_python}" == true ]]; then
        command -v python3 >/dev/null 2>&1 || missing_packages+=(python3)
    fi
    if [[ "${needs_venv}" == true ]]; then
        python3 -c 'import ensurepip' >/dev/null 2>&1 || missing_packages+=(python3-venv)
    fi
    if [[ "${#missing_packages[@]}" -eq 0 ]]; then
        log "Prerequisites already installed"
        return 0
    fi
    if [[ "${has_root}" != true ]]; then
        warn "missing ${missing_packages[*]}, and installing them needs root. Ask an administrator to install them, then rerun this script."
        exit 1
    fi
    log "Installing prerequisites: ${missing_packages[*]}"
    run_as_root apt-get update
    run_as_root apt-get install -y "${missing_packages[@]}"
}

# The homebrew Ansible role expects brew to exist, and dotfiles/install.sh
# needs bash 4+, which only Homebrew provides on macOS.
install_macos_prerequisites() {
    if ! xcode-select -p >/dev/null 2>&1; then
        warn "Xcode Command Line Tools are missing. Run 'xcode-select --install', then rerun this script."
        exit 1
    fi
    if ! activate_homebrew; then
        warn "Homebrew is missing. Install it from https://brew.sh, then rerun this script."
        exit 1
    fi
    if [[ "$(bash -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]]; then
        log "Installing bash 4+ with Homebrew"
        brew install bash
    fi
}

# Usage: install_prerequisites <has_root> <needs_python> <needs_venv>
install_prerequisites() {
    case "$(uname -s)" in
        Linux)
            if ! command -v apt-get >/dev/null 2>&1; then
                warn "only Debian-based Linux is supported (apt-get not found)"
                exit 1
            fi
            install_debian_prerequisites "$@"
            ;;
        Darwin) install_macos_prerequisites ;;
        *)
            warn "unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
}

# Clones over HTTPS because a fresh machine has no GitHub SSH key yet. Switch
# the remote to SSH later with `git remote set-url`.
clone_repository() {
    if [[ -d "${CHECKOUT_DIR}/.git" ]]; then
        log "Repository already cloned at ${CHECKOUT_DIR}"
        return 0
    fi
    log "Cloning ${REPOSITORY_URL} into ${CHECKOUT_DIR}"
    mkdir -p "$(dirname "${CHECKOUT_DIR}")"
    git clone "${REPOSITORY_URL}" "${CHECKOUT_DIR}"
}

# Points chezmoi at the checkout, so a later plain `chezmoi apply` uses it. A
# bare TOML key below a [table] header joins that table, so the line goes on
# top of an existing file.
configure_chezmoi_source() {
    local config_path="${XDG_CONFIG_HOME:-${HOME}/.config}/chezmoi/chezmoi.toml"
    if [[ ! -f "${config_path}" ]]; then
        mkdir -p "$(dirname "${config_path}")"
        printf '%s\n' "${CHEZMOI_SOURCE_DIR_LINE}" >"${config_path}"
        log "Created ${config_path}"
        return 0
    fi
    if grep -qE '^[[:space:]]*sourceDir[[:space:]]*=' "${config_path}"; then
        log "Keeping the sourceDir already set in ${config_path}"
        return 0
    fi
    local updated_config
    updated_config="$(printf '%s\n' "${CHEZMOI_SOURCE_DIR_LINE}"; cat "${config_path}")"
    printf '%s\n' "${updated_config}" >"${config_path}"
    log "Added sourceDir to ${config_path}"
}

# Installs chezmoi, applies the dotfiles, and installs the minimal CLI tools
# (ghq among them) through mise. Ansible runs afterwards because its roles
# read ghq and mise from the environment this step creates.
apply_dotfiles() {
    configure_chezmoi_source
    local modern_bash="bash"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        modern_bash="$(brew --prefix)/bin/bash"
    fi
    "${modern_bash}" "${CHECKOUT_DIR}/dotfiles/install.sh" --tools
}

# Installs Ansible into a private virtualenv. Debian 12+ refuses a system-wide
# pip install (PEP 668), and a venv keeps the version independent of apt.
install_ansible() {
    if [[ -x "${ANSIBLE_VENV_DIR}/bin/ansible-playbook" ]]; then
        log "Ansible already installed in ${ANSIBLE_VENV_DIR}"
        return 0
    fi
    log "Installing Ansible into ${ANSIBLE_VENV_DIR}"
    mkdir -p "$(dirname "${ANSIBLE_VENV_DIR}")"
    python3 -m venv "${ANSIBLE_VENV_DIR}"
    "${ANSIBLE_VENV_DIR}/bin/pip" install --upgrade pip
    "${ANSIBLE_VENV_DIR}/bin/pip" install ansible
}

# Prints the ansible-playbook flag that prompts for the sudo password, or
# nothing when sudo works without one. `-k` ignores the credentials cached by
# the apt-get step, which can expire in the middle of a long playbook run.
build_become_arguments() {
    if sudo -k -n true >/dev/null 2>&1; then
        return 0
    fi
    printf '%s\n' "--ask-become-pass"
}

run_playbook() {
    local playbook_name="$1"
    local -a become_arguments=()
    local become_argument
    become_argument="$(build_become_arguments)"
    if [[ -n "${become_argument}" ]]; then
        become_arguments+=("${become_argument}")
    fi

    log "Running ansible/${playbook_name}.yml"
    (
        cd "${CHECKOUT_DIR}/ansible"
        "${ANSIBLE_VENV_DIR}/bin/ansible-galaxy" collection install -r requirements.yml
        "${ANSIBLE_VENV_DIR}/bin/ansible-playbook" -i localhost, -c local \
            "${playbook_name}.yml" ${become_arguments[@]+"${become_arguments[@]}"}
    )
}

# Builds Emacs from source under ~/.local. The script needs no root, so this
# step also runs on a host where the playbooks cannot.
build_emacs() {
    log "Building Emacs with emacs.d/scripts/build_emacs.py"
    python3 "${CHECKOUT_DIR}/emacs.d/scripts/build_emacs.py"
}

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [--playbook main|minimal|ax8-max] [--skip-dotfiles]
                    [--skip-ansible] [--no-sudo] [--build-emacs]
                    [-h|--help]

Sets up this machine from nothing:
  1. Installs the prerequisites (git, curl, python3-venv; Homebrew bash on macOS).
  2. Clones garaemon-settings into ~/ghq/github.com/garaemon/garaemon-settings.
  3. Applies the dotfiles with chezmoi and installs CLI tools (ghq, ...) via mise.
  4. Installs Ansible into a virtualenv and runs the chosen playbook.

Every step skips work that is already done, so rerunning is safe.

Without root (no sudo command, or --no-sudo), the script runs steps 2 and 3
only. Steps 1 and 4 install system packages, so the script fails when a
prerequisite is missing and skips the playbook.

Options:
  --playbook NAME   Playbook under ansible/ to run (default: main).
  --skip-dotfiles   Skip step 3.
  --skip-ansible    Skip step 4.
  --no-sudo         Never use sudo, even when it is installed.
  --build-emacs     Build Emacs from source into ~/.local as a last step.
                    The build needs no root.
  -h, --help        Show this help and exit.
EOF
}

assert_allowed_playbook() {
    local playbook_name="$1"
    local allowed_playbook
    for allowed_playbook in ${ALLOWED_PLAYBOOKS}; do
        [[ "${playbook_name}" == "${allowed_playbook}" ]] && return 0
    done
    warn "unknown playbook: ${playbook_name} (expected one of: ${ALLOWED_PLAYBOOKS})"
    exit 2
}

main() {
    local playbook_name="main"
    local should_apply_dotfiles=true
    local should_run_ansible=true
    local is_sudo_allowed=true
    local should_build_emacs=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --playbook)
                if [[ $# -lt 2 ]]; then
                    warn "--playbook needs a value"
                    exit 2
                fi
                playbook_name="$2"
                shift
                ;;
            --playbook=*) playbook_name="${1#*=}" ;;
            --skip-dotfiles) should_apply_dotfiles=false ;;
            --skip-ansible) should_run_ansible=false ;;
            --no-sudo) is_sudo_allowed=false ;;
            --build-emacs) should_build_emacs=true ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                warn "unknown argument: $1"
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
    assert_allowed_playbook "${playbook_name}"

    local has_root=false
    if [[ "${is_sudo_allowed}" == true ]] && has_root_access; then
        has_root=true
    fi
    local will_run_ansible="${should_run_ansible}"
    if [[ "${has_root}" != true && "${should_run_ansible}" == true ]]; then
        log "Skipping Ansible: running without root, and the playbooks install system packages"
        will_run_ansible=false
    fi

    # The mise Ansible role runs `which mise` and reinstalls mise when the
    # binary that install.sh put in ~/.local/bin is not on PATH.
    export PATH="${HOME}/.local/bin:${PATH}"

    local needs_python="${will_run_ansible}"
    if [[ "${should_build_emacs}" == true ]]; then
        needs_python=true
    fi
    install_prerequisites "${has_root}" "${needs_python}" "${will_run_ansible}"
    clone_repository
    if [[ "${should_apply_dotfiles}" == true ]]; then
        apply_dotfiles
    fi
    if [[ "${will_run_ansible}" == true ]]; then
        install_ansible
        run_playbook "${playbook_name}"
    fi
    if [[ "${should_build_emacs}" == true ]]; then
        build_emacs
    fi
    log "Done. Open a new login shell to pick up the dotfiles."
}

# Skip the entry point when the test suite sources this file.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
