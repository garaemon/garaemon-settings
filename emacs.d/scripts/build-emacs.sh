#!/bin/bash
set -euo pipefail

# Builds Emacs from the emacs-mirror git repository and installs it under a
# user prefix without root. The Ansible emacs role installs the system build
# dependencies with apt and then calls this script, so a host with sudo and a
# host without it build Emacs the same way.
#
# Without root, the script cannot install system packages. It builds the
# small tools that a Debian host often lacks (m4, autoconf, makeinfo,
# tree-sitter) into the prefix instead, and it drops the features whose
# libraries are missing (GUI, native compilation, GnuTLS).

readonly DEFAULT_EMACS_VERSION="emacs-31.1"
readonly EMACS_REPOSITORY_URL="https://github.com/emacs-mirror/emacs"
readonly TREE_SITTER_REPOSITORY_URL="https://github.com/tree-sitter/tree-sitter"
readonly TREE_SITTER_VERSION="v0.25.9"
readonly GNU_MIRROR_URL="https://ftp.gnu.org/gnu"
# Each entry is "name version sha256" of a GNU release tarball (.tar.xz).
readonly GNU_M4_RELEASE="m4 1.4.19 63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96"
readonly GNU_AUTOCONF_RELEASE="autoconf 2.72 ba885c1319578d6c94d46e9b0dceb4014caafe2490e437a0dbca3f270a223f5a"
readonly GNU_TEXINFO_RELEASE="texinfo 7.2 0329d7788fbef113fa82cb80889ca197a344ce0df7646fe000974c5d714363a6"
readonly BUILD_STAMP_NAME=".built-emacs-version"
readonly MAX_DEFAULT_JOBS=4
# --check exits with this status when a build is due, so that a caller can
# tell "build needed" apart from a failure of the script itself.
readonly EXIT_CODE_BUILD_NEEDED=10

log() {
    printf '[build-emacs] %s\n' "$*"
}

warn() {
    printf '[build-emacs] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[build-emacs] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: build-emacs.sh [options]

Builds Emacs from https://github.com/emacs-mirror/emacs and installs it under
a prefix. The script needs no root: it builds missing m4, autoconf, makeinfo,
and tree-sitter into the prefix, and it turns off the GUI, native compilation,
or GnuTLS when their libraries are missing. It skips the build when the Emacs
under the prefix is already at least the requested version.

Options:
  --version TAG      Git tag or branch to build (default: emacs-31.1).
  --prefix DIR       Installation prefix (default: ~/.local).
  --source-dir DIR   Emacs checkout to build in
                     (default: $GHQ_ROOT/github.com/emacs-mirror/emacs,
                     with GHQ_ROOT defaulting to ~/ghq).
  --jobs N           Parallel make jobs (default: CPU count, at most 4).
  --gui MODE         auto, pgtk, or none (default: auto, which picks pgtk
                     when the GTK 3 headers are installed).
  --force            Build even when the installed Emacs is current.
  --check            Build nothing. Exit 0 when the installed Emacs is
                     current, and 10 when a build is due.
  -h, --help         Show this help and exit.
EOF
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prints the numeric part of a release tag ("emacs-31.1" -> "31.1"), or
# nothing for a branch name such as "master".
extract_numeric_version() {
    local version_tag="$1"
    local numeric_version="${version_tag#emacs-}"
    if [[ "${numeric_version}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
        printf '%s' "${numeric_version}"
    fi
}

is_version_at_least() {
    local installed_version="$1"
    local required_version="$2"
    local lowest_version
    lowest_version="$(printf '%s\n%s\n' "${installed_version}" "${required_version}" | sort -V | head -n 1)"
    [[ "${lowest_version}" == "${required_version}" ]]
}

read_installed_emacs_version() {
    local emacs_path="${INSTALL_PREFIX}/bin/emacs"
    [[ -x "${emacs_path}" ]] || return 0
    "${emacs_path}" --batch --eval '(princ emacs-version)' 2>/dev/null || true
}

# Succeeds when the Emacs under the prefix makes a build unnecessary. A branch
# name has no version to compare against, so it always needs a build.
is_installed_emacs_current() {
    [[ "${IS_FORCED}" == true ]] && return 1
    local required_version installed_version
    required_version="$(extract_numeric_version "${EMACS_VERSION}")"
    [[ -n "${required_version}" ]] || return 1
    installed_version="$(read_installed_emacs_version)"
    [[ -n "${installed_version}" ]] || return 1
    is_version_at_least "${installed_version}" "${required_version}"
}

detect_default_jobs() {
    local cpu_count
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
    if ((cpu_count > MAX_DEFAULT_JOBS)); then
        cpu_count="${MAX_DEFAULT_JOBS}"
    fi
    printf '%s' "${cpu_count}"
}

# Sets the configuration globals from the command line. Exits with status 2
# on a usage error.
parse_arguments() {
    EMACS_VERSION="${DEFAULT_EMACS_VERSION}"
    INSTALL_PREFIX="${HOME}/.local"
    SOURCE_DIR="${GHQ_ROOT:-${HOME}/ghq}/github.com/emacs-mirror/emacs"
    BUILD_JOBS="$(detect_default_jobs)"
    GUI_MODE="auto"
    IS_FORCED=false
    IS_CHECK_ONLY=false
    while [[ $# -gt 0 ]]; do
        local option_name="$1"
        local option_value=""
        case "${option_name}" in
            --*=*)
                option_value="${option_name#*=}"
                option_name="${option_name%%=*}"
                ;;
            --version | --prefix | --source-dir | --jobs | --gui)
                if [[ $# -lt 2 ]]; then
                    printf '%s needs a value\n' "${option_name}" >&2
                    exit 2
                fi
                option_value="$2"
                shift
                ;;
        esac
        case "${option_name}" in
            --version) EMACS_VERSION="${option_value}" ;;
            --prefix) INSTALL_PREFIX="${option_value}" ;;
            --source-dir) SOURCE_DIR="${option_value}" ;;
            --jobs) BUILD_JOBS="${option_value}" ;;
            --gui) GUI_MODE="${option_value}" ;;
            --force) IS_FORCED=true ;;
            --check) IS_CHECK_ONLY=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                printf 'unknown argument: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
    case "${GUI_MODE}" in
        auto | pgtk | none) ;;
        *)
            printf 'unknown --gui mode: %s (expected auto, pgtk, or none)\n' "${GUI_MODE}" >&2
            exit 2
            ;;
    esac
}

# Emacs looks up tputs in one of these libraries. The linker finds one only
# when the -dev package installs the unversioned .so symlink.
has_terminal_library() {
    local library_name
    for library_name in tinfo ncurses curses termcap; do
        if printf 'int main(void) { return 0; }\n' |
            cc -x c - "-l${library_name}" -o /dev/null >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Prints the Debian packages of the requirements that the script cannot
# build by itself, one per line.
list_missing_requirements() {
    command_exists git || echo git
    command_exists cc || command_exists gcc || echo gcc
    command_exists make || echo make
    command_exists pkg-config || echo pkg-config
    command_exists perl || echo perl
    command_exists curl || echo curl
    command_exists xz || echo xz-utils
    has_terminal_library || echo libncurses-dev
}

assert_requirements() {
    local missing_packages
    missing_packages="$(list_missing_requirements | tr '\n' ' ')"
    if [[ -n "${missing_packages}" ]]; then
        die "missing requirements. Ask an administrator to install: ${missing_packages}"
    fi
}

# Makes the tools and libraries built into the prefix visible to configure,
# and records the prefix as a runtime search path so that emacs finds a
# tree-sitter installed there.
export_prefix_paths() {
    export PATH="${INSTALL_PREFIX}/bin:${PATH}"
    export PKG_CONFIG_PATH="${INSTALL_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    export CPPFLAGS="-I${INSTALL_PREFIX}/include${CPPFLAGS:+ ${CPPFLAGS}}"
    export LDFLAGS="-L${INSTALL_PREFIX}/lib -Wl,-rpath,${INSTALL_PREFIX}/lib${LDFLAGS:+ ${LDFLAGS}}"
}

# Debian installs libgccjit.so in the private GCC directory, which the linker
# does not search. libgccjit also reads LIBRARY_PATH at run time to find
# libgcc when Emacs compiles a .eln file.
export_gccjit_paths() {
    command_exists gcc || return 0
    local gcc_library_dir
    gcc_library_dir="$(dirname "$(gcc -print-libgcc-file-name)")"
    export LIBRARY_PATH="${gcc_library_dir}${LIBRARY_PATH:+:${LIBRARY_PATH}}"
    export LDFLAGS="${LDFLAGS} -L${gcc_library_dir}"
}

download_cache_dir() {
    printf '%s' "${XDG_CACHE_HOME:-${HOME}/.cache}/build-emacs"
}

# Builds a GNU package from its release tarball and installs it into the
# prefix. The argument is one of the GNU_*_RELEASE entries.
install_gnu_package() {
    local package_name package_version expected_sha256
    read -r package_name package_version expected_sha256 <<<"$1"
    local cache_dir archive_name
    cache_dir="$(download_cache_dir)"
    archive_name="${package_name}-${package_version}.tar.xz"
    mkdir -p "${cache_dir}"
    log "Building ${package_name} ${package_version} into ${INSTALL_PREFIX}"
    curl -fsSL -o "${cache_dir}/${archive_name}" \
        "${GNU_MIRROR_URL}/${package_name}/${archive_name}"
    if ! printf '%s  %s\n' "${expected_sha256}" "${cache_dir}/${archive_name}" |
        sha256sum --check --status; then
        die "checksum mismatch for ${archive_name}"
    fi
    rm -rf "${cache_dir:?}/${package_name}-${package_version}"
    tar -xJf "${cache_dir}/${archive_name}" -C "${cache_dir}"
    (
        cd "${cache_dir}/${package_name}-${package_version}"
        ./configure --prefix="${INSTALL_PREFIX}"
        make -j "${BUILD_JOBS}"
        make install
    )
}

# autoconf runs m4, and Emacs's autogen.sh requires autoconf. A checkout from
# git carries no prebuilt manuals, so configure also requires makeinfo.
ensure_build_tools() {
    command_exists m4 || install_gnu_package "${GNU_M4_RELEASE}"
    command_exists autoconf || install_gnu_package "${GNU_AUTOCONF_RELEASE}"
    command_exists makeinfo || install_gnu_package "${GNU_TEXINFO_RELEASE}"
}

ensure_tree_sitter() {
    if pkg-config --exists tree-sitter; then
        return 0
    fi
    local tree_sitter_dir
    tree_sitter_dir="$(download_cache_dir)/tree-sitter-${TREE_SITTER_VERSION}"
    log "Building tree-sitter ${TREE_SITTER_VERSION} into ${INSTALL_PREFIX}"
    if [[ ! -d "${tree_sitter_dir}" ]]; then
        git clone --depth 1 --branch "${TREE_SITTER_VERSION}" \
            "${TREE_SITTER_REPOSITORY_URL}" "${tree_sitter_dir}"
    fi
    make -C "${tree_sitter_dir}" -j "${BUILD_JOBS}" PREFIX="${INSTALL_PREFIX}"
    make -C "${tree_sitter_dir}" PREFIX="${INSTALL_PREFIX}" install
}

# Fetches EMACS_VERSION into SOURCE_DIR and checks it out. A shallow checkout
# stays shallow, and a full clone keeps its history.
checkout_emacs_source() {
    if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
        log "Cloning ${EMACS_VERSION} into ${SOURCE_DIR}"
        mkdir -p "$(dirname "${SOURCE_DIR}")"
        git clone --depth 1 --branch "${EMACS_VERSION}" \
            "${EMACS_REPOSITORY_URL}" "${SOURCE_DIR}"
        return 0
    fi
    local -a depth_arguments=()
    if [[ "$(git -C "${SOURCE_DIR}" rev-parse --is-shallow-repository)" == true ]]; then
        depth_arguments=(--depth 1)
    fi
    log "Checking out ${EMACS_VERSION} in ${SOURCE_DIR}"
    git -C "${SOURCE_DIR}" fetch ${depth_arguments[@]+"${depth_arguments[@]}"} \
        origin "${EMACS_VERSION}"
    git -C "${SOURCE_DIR}" checkout --detach FETCH_HEAD
}

# make reuses the .elc and .eln files left in the tree. Artifacts from another
# Emacs version make the native compiler load a stale .eln and abort with
# "Recursive load". The stamp is written before the build, so a build that
# dies halfway resumes incrementally instead of cleaning again.
clean_stale_build_tree() {
    local stamp_path="${SOURCE_DIR}/${BUILD_STAMP_NAME}"
    local built_version=""
    if [[ -f "${stamp_path}" ]]; then
        built_version="$(<"${stamp_path}")"
    fi
    if [[ "${built_version}" == "${EMACS_VERSION}" ]]; then
        return 0
    fi
    log "Removing build artifacts that do not belong to ${EMACS_VERSION}"
    git -C "${SOURCE_DIR}" clean -xdf
    printf '%s\n' "${EMACS_VERSION}" >"${stamp_path}"
}

has_gtk3() {
    pkg-config --exists gtk+-3.0
}

has_usable_libgccjit() {
    local test_binary
    test_binary="$(mktemp)"
    local compile_status=0
    printf '#include <libgccjit.h>\nint main(void) { return gcc_jit_context_acquire() == 0; }\n' |
        gcc -x c - -lgccjit -o "${test_binary}" >/dev/null 2>&1 || compile_status=$?
    rm -f "${test_binary}"
    return "${compile_status}"
}

# Prints the configure arguments, one per line. Features whose libraries may
# be missing on a host without root use "ifavailable", so configure drops
# them instead of failing.
build_configure_arguments() {
    printf '%s\n' "--prefix=${INSTALL_PREFIX}" \
        --with-tree-sitter --with-gnutls=ifavailable --without-compress-install
    local gui_mode="${GUI_MODE}"
    if [[ "${gui_mode}" == auto ]]; then
        gui_mode=none
        has_gtk3 && gui_mode=pgtk
    fi
    if [[ "${gui_mode}" == pgtk ]]; then
        printf '%s\n' --with-pgtk --with-xpm=ifavailable --with-jpeg=ifavailable \
            --with-png=ifavailable --with-gif=ifavailable --with-tiff=ifavailable
    else
        printf '%s\n' --without-x
    fi
    if has_usable_libgccjit; then
        printf '%s\n' --with-native-compilation=aot
    else
        printf '%s\n' --with-native-compilation=no
    fi
}

build_and_install_emacs() {
    local -a configure_arguments=()
    local configure_argument
    while IFS= read -r configure_argument; do
        configure_arguments+=("${configure_argument}")
    done < <(build_configure_arguments)
    local -a make_variables=()
    if command_exists ccache; then
        make_variables=(CC="ccache gcc" CXX="ccache g++")
    fi
    log "Configuring Emacs: ${configure_arguments[*]}"
    (
        cd "${SOURCE_DIR}"
        ./autogen.sh
        ./configure "${configure_arguments[@]}"
        make ${make_variables[@]+"${make_variables[@]}"} -j "${BUILD_JOBS}"
        make install
    )
}

warn_about_missing_features() {
    local emacs_features
    emacs_features="$("${INSTALL_PREFIX}/bin/emacs" --batch \
        --eval '(princ system-configuration-features)')"
    log "Installed ${INSTALL_PREFIX}/bin/emacs with: ${emacs_features}"
    if [[ " ${emacs_features} " != *" GNUTLS "* ]]; then
        warn "no GnuTLS: package.el cannot reach https archives. Install libgnutls28-dev to enable it."
    fi
    if [[ " ${emacs_features} " != *" NATIVE_COMP "* ]]; then
        warn "no native compilation. Install libgccjit-<gcc version>-dev to enable it."
    fi
}

main() {
    parse_arguments "$@"
    if is_installed_emacs_current; then
        log "Emacs under ${INSTALL_PREFIX} is already ${EMACS_VERSION} or newer"
        return 0
    fi
    if [[ "${IS_CHECK_ONLY}" == true ]]; then
        return "${EXIT_CODE_BUILD_NEEDED}"
    fi
    assert_requirements
    export_prefix_paths
    export_gccjit_paths
    ensure_build_tools
    ensure_tree_sitter
    checkout_emacs_source
    clean_stale_build_tree
    build_and_install_emacs
    warn_about_missing_features
}

# Skip the entry point when the test suite sources this file.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    main "$@"
fi
