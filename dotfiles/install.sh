#!/usr/bin/env bash
# install.sh - Bootstrap script for VS Code dev container dotfiles support.
#
# When VS Code Dev Containers (or GitHub Codespaces) clones this repository
# as the user's dotfiles repo, it executes this script after cloning. The
# script installs a pinned, sha256-verified chezmoi release (if missing)
# and applies the dotfiles from the cloned working tree.
#
# Pass --tools (or --tools=minimal | --tools=all) to additionally install a
# set of CLI tools (starship, etc.) through a pinned, sha256-verified mise
# release. This is handy for bringing a fresh dev container up to a usable
# interactive shell in one shot. Run `install.sh --help` for details.
#
# See: https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories
# See: https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-github-codespaces-for-your-account

set -euo pipefail

# Require bash 4+ for associative arrays. On bash 3.x (notably the system
# bash on macOS), `declare -A` silently degrades to a plain indexed array
# whose keys all collapse to index 0, which would corrupt the checksum
# lookup below; fail fast instead.
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    printf '[dotfiles install] ERROR: bash 4 or later required (found %s)\n' \
        "${BASH_VERSION:-unknown}" >&2
    exit 1
fi

# Pinned chezmoi release. The scheduled workflow at
# .github/workflows/update-pinned-tools.yml refreshes both fields
# automatically by running
# `.github/scripts/update_pinned_tool.py --tool chezmoi` and opening a PR.
# To bump manually:
#   1. Pick a new tag from https://github.com/twpayne/chezmoi/releases.
#   2. Update CHEZMOI_VERSION below.
#   3. Update each entry in CHEZMOI_CHECKSUMS with the matching sha256
#      from the official chezmoi_<version>_checksums.txt for that release.
readonly CHEZMOI_VERSION="2.71.0"

# Pinned sha256 checksums of the chezmoi release tarballs, keyed by
# os_arch. Embedded here rather than fetched alongside the binary so that
# a compromised release artifact (or a network MITM that swaps both files)
# cannot match itself. Requires bash 4+ for associative arrays.
declare -rA CHEZMOI_CHECKSUMS=(
    [darwin_amd64]="12b78b365528597ad701f5117fa71f6c42b5b1e65d8075e19c48472ad81faf30"  # pragma: allowlist secret
    [darwin_arm64]="8b03d7be6b5d500a503c712ae6da7dd6817b6c3328223b4ae8be7a8be5a2fa3a"  # pragma: allowlist secret
    [linux_amd64]="6ea2040ecc0e82d3dac604289e100b0157afefcd94ebb818e5f6e31655156d34"  # pragma: allowlist secret
    [linux_arm64]="d8fb35f9d43237b4f6d022cad40e1094957b990cfaee5f3b131ded65422b0983"  # pragma: allowlist secret
)

# Pinned mise release, used only when tool installation is requested via
# --tools. mise is the same tool manager the dotfiles configure (see
# dot_config/mise/config.toml), so installing tools through it keeps versions
# consistent with day-to-day use. The scheduled workflow at
# .github/workflows/update-pinned-tools.yml refreshes both fields
# automatically by running
# `.github/scripts/update_pinned_tool.py --tool mise` and opening a PR.
# To bump manually:
#   1. Pick a new tag from https://github.com/jdx/mise/releases.
#   2. Update MISE_VERSION below (without the leading "v").
#   3. Update each entry in MISE_CHECKSUMS with the matching sha256 from the
#      release's SHASUMS256.txt. Note the platform keys use mise's naming
#      (linux-x64, macos-arm64, ...), not chezmoi's.
readonly MISE_VERSION="2026.7.0"

declare -rA MISE_CHECKSUMS=(
    [linux-x64]="a3ff8f55b61504e7d7556d7b0cac4413e0c85ef7279545d2c2c3f49bd2cf8472"  # pragma: allowlist secret
    [linux-arm64]="fcbba22dfd6bfaf94912fdba3e1f034c89841cda7a895fd2b7402cef3d7ae214"  # pragma: allowlist secret
    [macos-x64]="c33f2974806db45d5a2b0ab480d0750c54328c6fe87be5cf915106d46e55b9f0"  # pragma: allowlist secret
    [macos-arm64]="23efe18046d12b95895d17b2bf0101a0efb9bf174767c57b6e2c8d019b964252"  # pragma: allowlist secret
)

# Minimal set of tools installed by --tools (or --tools=minimal): the
# interactive-shell essentials the dotfiles lean on. Versions are resolved
# from the applied dot_config/mise/config.toml, so each name here must also
# appear there. Heavier language/cloud toolchains are intentionally excluded;
# use --tools=all to install everything declared in that config instead.
readonly MISE_MINIMAL_TOOLS=(
    starship
    bat
    ripgrep
    delta
    direnv
    jq
    peco
    ghq
)

# SCRIPT_DIR is where this script lives, which is also the chezmoi source
# directory because Dev Containers clones the entire repo into one place
# and runs install.sh from its root.
# Assigned then marked readonly in two steps so that a failure inside the
# command substitution (e.g. `cd` failure) propagates under `set -e`. A
# combined `readonly VAR="$(...)"` would swallow the substitution status.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# Where downloaded binaries (chezmoi, and mise when --tools is used) land.
readonly LOCAL_BIN_DIR="${HOME}/.local/bin"

# Writes a tagged informational message to stdout.
log() {
    printf '[dotfiles install] %s\n' "$*"
}

# Writes a tagged error message to stderr; use for failure paths and aborts.
warn() {
    printf '[dotfiles install] ERROR: %s\n' "$*" >&2
}

# Resolves the path to a usable chezmoi binary on stdout, or returns 1.
# The absolute-path fallback exists because ${LOCAL_BIN_DIR} may not be on
# PATH in the dev container's shell, even immediately after install_chezmoi
# drops the binary there.
resolve_chezmoi() {
    if command -v chezmoi >/dev/null 2>&1; then
        printf '%s\n' "$(command -v chezmoi)"
        return 0
    fi
    if [[ -x "${LOCAL_BIN_DIR}/chezmoi" ]]; then
        printf '%s\n' "${LOCAL_BIN_DIR}/chezmoi"
        return 0
    fi
    return 1
}

# Resolves the path to a usable mise binary on stdout, or returns 1. Mirrors
# resolve_chezmoi, including the absolute-path fallback for the common case
# where ${LOCAL_BIN_DIR} is not yet on PATH.
resolve_mise() {
    if command -v mise >/dev/null 2>&1; then
        printf '%s\n' "$(command -v mise)"
        return 0
    fi
    if [[ -x "${LOCAL_BIN_DIR}/mise" ]]; then
        printf '%s\n' "${LOCAL_BIN_DIR}/mise"
        return 0
    fi
    return 1
}

# Prints the platform suffix used in chezmoi release tarball names
# (e.g. "linux_amd64", "darwin_arm64") on stdout. Returns 1 for unsupported
# os/arch combinations.
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "${arch}" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            warn "unsupported architecture: ${arch}"
            return 1
            ;;
    esac
    case "${os}" in
        linux|darwin) ;;
        *)
            warn "unsupported os: ${os}"
            return 1
            ;;
    esac
    printf '%s_%s\n' "${os}" "${arch}"
}

# Computes the sha256 of a file on stdout. Prefers sha256sum (standard on
# Linux) and falls back to shasum (default on macOS).
compute_sha256() {
    local path="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${path}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${path}" | awk '{print $1}'
    else
        warn "neither sha256sum nor shasum is available; cannot verify checksum"
        return 1
    fi
}

# Prints the pinned chezmoi sha256 for a given platform key (e.g.
# "linux_amd64") on stdout, or returns 1 if no entry matches.
lookup_checksum() {
    local platform="$1"
    local checksum="${CHEZMOI_CHECKSUMS[${platform}]:-}"
    if [[ -z "${checksum}" ]]; then
        warn "no pinned checksum for platform ${platform}"
        return 1
    fi
    printf '%s\n' "${checksum}"
}

# Prints the pinned mise sha256 for a given mise platform key (e.g.
# "linux-x64") on stdout, or returns 1 if no entry matches. Kept a separate
# function (rather than indexing MISE_CHECKSUMS inline) so the test suite can
# override it to exercise the checksum-mismatch path; the array is readonly
# and cannot be reassigned.
lookup_mise_checksum() {
    local platform="$1"
    local checksum="${MISE_CHECKSUMS[${platform}]:-}"
    if [[ -z "${checksum}" ]]; then
        warn "no pinned checksum for mise platform ${platform}"
        return 1
    fi
    printf '%s\n' "${checksum}"
}

# Downloads chezmoi v${CHEZMOI_VERSION} for the current platform, verifies
# its sha256 against the pinned checksum, and installs the binary into
# ${CHEZMOI_BIN_DIR}. Skips the install if a chezmoi binary is already
# resolvable.
install_chezmoi() {
    local existing_path
    if existing_path="$(resolve_chezmoi)"; then
        log "chezmoi already installed at ${existing_path}"
        return 0
    fi

    local platform tarball url expected actual tmpdir tarball_path
    platform="$(detect_platform)"
    tarball="chezmoi_${CHEZMOI_VERSION}_${platform}.tar.gz"
    url="https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/${tarball}"
    expected="$(lookup_checksum "${platform}")"

    tmpdir="$(mktemp -d)"
    # Expand ${tmpdir} into the trap body now (double quotes) so cleanup
    # targets the directory we just created even if the variable is later
    # reassigned.
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT
    tarball_path="${tmpdir}/${tarball}"

    log "Downloading chezmoi v${CHEZMOI_VERSION} for ${platform}"
    curl -fsSL -o "${tarball_path}" "${url}"

    actual="$(compute_sha256 "${tarball_path}")"
    if [[ "${actual}" != "${expected}" ]]; then
        warn "sha256 mismatch for ${tarball}"
        warn "  expected: ${expected}"
        warn "  actual:   ${actual}"
        exit 1
    fi
    log "Verified sha256 for ${tarball}"

    mkdir -p "${LOCAL_BIN_DIR}"
    tar -xzf "${tarball_path}" -C "${tmpdir}" chezmoi
    mv "${tmpdir}/chezmoi" "${LOCAL_BIN_DIR}/chezmoi"
    chmod 0755 "${LOCAL_BIN_DIR}/chezmoi"

    # Clean up now and clear the EXIT trap so a later install_mise can install
    # its own trap without leaking this tmpdir at script exit.
    rm -rf "${tmpdir}"
    trap - EXIT

    log "Installed chezmoi v${CHEZMOI_VERSION} to ${LOCAL_BIN_DIR}/chezmoi"
    log "Note: add ${LOCAL_BIN_DIR} to PATH to use chezmoi directly later"
}

# Prints mise's platform suffix (e.g. "linux-x64", "macos-arm64") on stdout
# for a chezmoi-style platform key (e.g. "linux_amd64", "darwin_arm64") as
# emitted by detect_platform. mise names its release tarballs differently
# from chezmoi, so the two cannot share a single platform string. Returns 1
# for combinations mise does not publish.
mise_platform() {
    case "$1" in
        linux_amd64) printf 'linux-x64\n' ;;
        linux_arm64) printf 'linux-arm64\n' ;;
        darwin_amd64) printf 'macos-x64\n' ;;
        darwin_arm64) printf 'macos-arm64\n' ;;
        *)
            warn "unsupported platform for mise: $1"
            return 1
            ;;
    esac
}

# Downloads mise v${MISE_VERSION} for the current platform, verifies its
# sha256 against the pinned checksum, and installs the binary into
# ${LOCAL_BIN_DIR}. Skips the install if a mise binary is already resolvable.
# Mirrors install_chezmoi; only the tarball layout (mise/bin/mise) differs.
install_mise() {
    local existing_path
    if existing_path="$(resolve_mise)"; then
        log "mise already installed at ${existing_path}"
        return 0
    fi

    local platform mise_plat tarball url expected actual tmpdir tarball_path
    platform="$(detect_platform)"
    mise_plat="$(mise_platform "${platform}")"
    tarball="mise-v${MISE_VERSION}-${mise_plat}.tar.gz"
    url="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/${tarball}"
    expected="$(lookup_mise_checksum "${mise_plat}")"

    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT
    tarball_path="${tmpdir}/${tarball}"

    log "Downloading mise v${MISE_VERSION} for ${mise_plat}"
    curl -fsSL -o "${tarball_path}" "${url}"

    actual="$(compute_sha256 "${tarball_path}")"
    if [[ "${actual}" != "${expected}" ]]; then
        warn "sha256 mismatch for ${tarball}"
        warn "  expected: ${expected}"
        warn "  actual:   ${actual}"
        exit 1
    fi
    log "Verified sha256 for ${tarball}"

    mkdir -p "${LOCAL_BIN_DIR}"
    # mise tarballs unpack to mise/bin/mise (plus man pages and shell hooks);
    # extract just the binary.
    tar -xzf "${tarball_path}" -C "${tmpdir}" "mise/bin/mise"
    mv "${tmpdir}/mise/bin/mise" "${LOCAL_BIN_DIR}/mise"
    chmod 0755 "${LOCAL_BIN_DIR}/mise"

    rm -rf "${tmpdir}"
    trap - EXIT

    log "Installed mise v${MISE_VERSION} to ${LOCAL_BIN_DIR}/mise"
}

# Installs CLI tools via mise. mode is "minimal" (the curated
# ${MISE_MINIMAL_TOOLS} set) or "all" (everything declared in the applied
# dot_config/mise/config.toml). Either way, tool versions come from that
# config, so apply_dotfiles must have run first. MISE_YES keeps mise
# non-interactive for unattended dev container builds.
install_tools() {
    local mode="$1"
    local mise_cmd
    if ! mise_cmd="$(resolve_mise)"; then
        warn "mise binary not found after install; aborting"
        exit 1
    fi

    if [[ "${mode}" == "all" ]]; then
        log "Installing all tools declared in mise config"
        MISE_YES=1 "${mise_cmd}" install --yes
    else
        log "Installing minimal tool set: ${MISE_MINIMAL_TOOLS[*]}"
        MISE_YES=1 "${mise_cmd}" install --yes "${MISE_MINIMAL_TOOLS[@]}"
    fi
    log "Tools installed; add ${LOCAL_BIN_DIR} to PATH and run 'mise activate' in your shell"
}

# Applies the dotfiles in ${SCRIPT_DIR} to the user's home directory using
# chezmoi.
apply_dotfiles() {
    local chezmoi_cmd
    if ! chezmoi_cmd="$(resolve_chezmoi)"; then
        warn "chezmoi binary not found after install; aborting"
        exit 1
    fi

    log "Applying dotfiles from ${SCRIPT_DIR}"
    # Use `apply --source=` rather than `init --apply` to avoid any chance
    # of an interactive prompt (init can prompt when a chezmoi.toml.tmpl
    # exists), which would hang an unattended dev container build.
    "${chezmoi_cmd}" apply --source="${SCRIPT_DIR}"
}

# Prints usage to stdout.
usage() {
    cat <<'EOF'
Usage: install.sh [--tools[=minimal|all]] [-h|--help]

Installs a pinned, sha256-verified chezmoi release (if missing) and applies
the dotfiles from this repository. Safe to run unattended; this is what VS
Code Dev Containers / GitHub Codespaces invoke after cloning.

Options:
  --tools, --tools=minimal
        Also install the interactive-shell essentials (starship, bat,
        ripgrep, delta, direnv, jq, peco, ghq) through a pinned,
        sha256-verified mise release. Versions come from
        dot_config/mise/config.toml.
  --tools=all
        Install every tool declared in dot_config/mise/config.toml instead.
        This pulls in heavy language/cloud toolchains and can take a while.
  -h, --help
        Show this help and exit.
EOF
}

main() {
    local tools_mode=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tools) tools_mode="minimal" ;;
            --tools=*) tools_mode="${1#*=}" ;;
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

    case "${tools_mode}" in
        ""|minimal|all) ;;
        *)
            warn "invalid --tools value: '${tools_mode}' (expected 'minimal' or 'all')"
            exit 2
            ;;
    esac

    install_chezmoi
    apply_dotfiles
    if [[ -n "${tools_mode}" ]]; then
        install_mise
        install_tools "${tools_mode}"
    fi
    log "Done."
}

# Run main only when this file is executed directly. When sourced (e.g. by
# the test suite to call individual functions), skip the entry point.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
