#!/usr/bin/env bash
# install.sh - Bootstrap script for VS Code dev container dotfiles support.
#
# When VS Code Dev Containers (or GitHub Codespaces) clones this repository
# as the user's dotfiles repo, it executes this script after cloning. The
# script installs a pinned, sha256-verified chezmoi release (if missing)
# and applies the dotfiles from the cloned working tree.
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
# .github/workflows/update-chezmoi.yml refreshes both fields automatically
# by running .github/scripts/update_chezmoi.py and opening a PR. To bump
# manually:
#   1. Pick a new tag from https://github.com/twpayne/chezmoi/releases.
#   2. Update CHEZMOI_VERSION below.
#   3. Update each entry in CHEZMOI_CHECKSUMS with the matching sha256
#      from the official chezmoi_<version>_checksums.txt for that release.
readonly CHEZMOI_VERSION="2.70.4"

# Pinned sha256 checksums of the chezmoi release tarballs, keyed by
# os_arch. Embedded here rather than fetched alongside the binary so that
# a compromised release artifact (or a network MITM that swaps both files)
# cannot match itself. Requires bash 4+ for associative arrays.
declare -rA CHEZMOI_CHECKSUMS=(
    [darwin_amd64]="df605c409f16ff9ce002bd2690755c4c0aa6357ca4a065ed2f3cc7936a9f448e"  # pragma: allowlist secret
    [darwin_arm64]="0093fa436e9ccccf423323315c0146f6dc77985294bd845cee1f3cf3f63eeb0f"  # pragma: allowlist secret
    [linux_amd64]="7382f585d35647ebb492bd6345466e7f35564068b78285bb029cb2f35056ecf4"  # pragma: allowlist secret
    [linux_arm64]="b2dc1e0ddf8beff09ee14f212271dd9e943d1d97d5f17a3d070ce35a6ada9e14"  # pragma: allowlist secret
)

# SCRIPT_DIR is where this script lives, which is also the chezmoi source
# directory because Dev Containers clones the entire repo into one place
# and runs install.sh from its root.
# Assigned then marked readonly in two steps so that a failure inside the
# command substitution (e.g. `cd` failure) propagates under `set -e`. A
# combined `readonly VAR="$(...)"` would swallow the substitution status.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly CHEZMOI_BIN_DIR="${HOME}/.local/bin"

# Writes a tagged informational message to stdout.
log() {
    printf '[dotfiles install] %s\n' "$*"
}

# Writes a tagged error message to stderr; use for failure paths and aborts.
warn() {
    printf '[dotfiles install] ERROR: %s\n' "$*" >&2
}

# Resolves the path to a usable chezmoi binary on stdout, or returns 1.
# The absolute-path fallback exists because ${CHEZMOI_BIN_DIR} may not be on
# PATH in the dev container's shell, even immediately after install_chezmoi
# drops the binary there.
resolve_chezmoi() {
    if command -v chezmoi >/dev/null 2>&1; then
        printf '%s\n' "$(command -v chezmoi)"
        return 0
    fi
    if [[ -x "${CHEZMOI_BIN_DIR}/chezmoi" ]]; then
        printf '%s\n' "${CHEZMOI_BIN_DIR}/chezmoi"
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

# Prints the pinned sha256 for a given platform key (e.g. "linux_amd64")
# on stdout, or returns 1 if no entry matches.
lookup_checksum() {
    local platform="$1"
    local checksum="${CHEZMOI_CHECKSUMS[${platform}]:-}"
    if [[ -z "${checksum}" ]]; then
        warn "no pinned checksum for platform ${platform}"
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

    mkdir -p "${CHEZMOI_BIN_DIR}"
    tar -xzf "${tarball_path}" -C "${tmpdir}" chezmoi
    mv "${tmpdir}/chezmoi" "${CHEZMOI_BIN_DIR}/chezmoi"
    chmod 0755 "${CHEZMOI_BIN_DIR}/chezmoi"

    log "Installed chezmoi v${CHEZMOI_VERSION} to ${CHEZMOI_BIN_DIR}/chezmoi"
    log "Note: add ${CHEZMOI_BIN_DIR} to PATH to use chezmoi directly later"
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

main() {
    install_chezmoi
    apply_dotfiles
    log "Done."
}

# Run main only when this file is executed directly. When sourced (e.g. by
# the test suite to call individual functions), skip the entry point.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
