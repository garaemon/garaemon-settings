#!/usr/bin/env python3
"""Build Emacs from the emacs-mirror git repository without root.

The Ansible emacs role installs the system build dependencies with apt and
then runs this script, so a host with sudo and a host without it build Emacs
the same way.

Without root, the script cannot install system packages. It builds the small
tools that a Debian host often lacks (m4, autoconf, makeinfo, tree-sitter)
into the prefix instead, and it drops the features whose libraries are
missing (GUI, native compilation, GnuTLS).

The script uses the standard library only and runs on Python 3.8 or later.
"""

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path
from typing import Dict, List, NamedTuple, NoReturn, Optional

DEFAULT_EMACS_VERSION = "emacs-31.1"
EMACS_REPOSITORY_URL = "https://github.com/emacs-mirror/emacs"
TREE_SITTER_REPOSITORY_URL = "https://github.com/tree-sitter/tree-sitter"
TREE_SITTER_VERSION = "v0.25.9"
# A tag can be moved, so the clone must resolve to this commit of the tag.
TREE_SITTER_COMMIT = "a467ea8502d95562171f97953a6dc5b2a8622609"
GNU_MIRROR_URL = "https://ftp.gnu.org/gnu"
BUILD_STAMP_NAME = ".built-emacs-version"
# --check exits with this status when a build is due, so that a caller can
# tell "build needed" apart from a failure of the script itself.
EXIT_CODE_BUILD_NEEDED = 10
# Seconds without data before a download is abandoned. urlopen otherwise
# waits forever on a mirror that accepts the connection and then stalls.
DOWNLOAD_TIMEOUT_SECONDS = 60


class GnuRelease(NamedTuple):
    name: str
    version: str
    sha256: str


GNU_M4 = GnuRelease(
    "m4", "1.4.19",
    "63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96")
GNU_AUTOCONF = GnuRelease(
    "autoconf", "2.72",
    "ba885c1319578d6c94d46e9b0dceb4014caafe2490e437a0dbca3f270a223f5a")
GNU_TEXINFO = GnuRelease(
    "texinfo", "7.2",
    "0329d7788fbef113fa82cb80889ca197a344ce0df7646fe000974c5d714363a6")


def log(message: str) -> None:
    print(f"[build-emacs] {message}", flush=True)


def warn(message: str) -> None:
    print(f"[build-emacs] WARNING: {message}", file=sys.stderr, flush=True)


def die(message: str) -> NoReturn:
    sys.exit(f"[build-emacs] ERROR: {message}")


def run(command: List[str], **kwargs) -> None:
    """Run command and stop the script when it fails."""
    subprocess.run(command, check=True, **kwargs)


def succeeds(command: List[str], **kwargs) -> bool:
    """Return whether command exits with status 0, hiding its output."""
    try:
        completed = subprocess.run(
            command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            **kwargs)
    except FileNotFoundError:
        return False
    return completed.returncode == 0


def count_available_cpus() -> int:
    """Return the number of CPUs that this process may run on.

    The affinity mask reflects a taskset or cgroup cpuset limit on a shared
    host, while os.cpu_count() counts every CPU of the machine. macOS lacks
    sched_getaffinity.
    """
    if hasattr(os, "sched_getaffinity"):
        return len(os.sched_getaffinity(0))
    return os.cpu_count() or 1


def parse_arguments(argv: List[str]) -> argparse.Namespace:
    """Return the options; argparse exits with status 2 on a usage error."""
    home = Path.home()
    ghq_root = Path(os.environ.get("GHQ_ROOT", home / "ghq"))
    parser = argparse.ArgumentParser(
        description=(
            "Build Emacs from emacs-mirror and install it under a prefix "
            "without root. Missing m4, autoconf, makeinfo, and tree-sitter "
            "are built into the prefix. The build skips the GUI, native "
            "compilation, or GnuTLS when their libraries are missing."))
    parser.add_argument(
        "--version", default=DEFAULT_EMACS_VERSION,
        help="git tag or branch to build (default: %(default)s)")
    parser.add_argument(
        "--prefix", type=Path, default=home / ".local",
        help="installation prefix (default: ~/.local)")
    parser.add_argument(
        "--source-dir", type=Path,
        default=ghq_root / "github.com" / "emacs-mirror" / "emacs",
        help="Emacs checkout to build in (default: under $GHQ_ROOT or ~/ghq)")
    parser.add_argument(
        "--jobs", type=int, default=count_available_cpus(),
        help="parallel make jobs (default: available CPUs)")
    parser.add_argument(
        "--gui", choices=("auto", "pgtk", "none"), default="auto",
        help="auto picks pgtk when the GTK 3 headers exist (default: auto)")
    parser.add_argument(
        "--gnutls", choices=("auto", "yes"), default="auto",
        help="auto builds without GnuTLS when its headers are missing, and "
             "yes makes configure fail instead (default: auto)")
    parser.add_argument(
        "--sqlite", choices=("auto", "yes"), default="auto",
        help="auto builds without SQLite when its headers are missing, and "
             "yes stops before the build instead (default: auto)")
    parser.add_argument(
        "--native-compilation", choices=("auto", "aot", "no"),
        default="auto",
        help="auto compiles ahead of time when libgccjit links, and aot "
             "makes configure fail without it (default: auto)")
    parser.add_argument(
        "--force", action="store_true",
        help="build even when the installed Emacs is current")
    parser.add_argument(
        "--check", action="store_true",
        help=f"build nothing; exit 0 when the installed Emacs is current, "
             f"and {EXIT_CODE_BUILD_NEEDED} when a build is due")
    return parser.parse_args(argv)


def extract_numeric_version(version_tag: str) -> Optional[str]:
    """Return "31.1" for "emacs-31.1", or None for a branch name."""
    numeric_version = version_tag[len("emacs-"):] \
        if version_tag.startswith("emacs-") else version_tag
    if re.fullmatch(r"[0-9]+(\.[0-9]+)*", numeric_version):
        return numeric_version
    return None


def is_version_at_least(installed_version: str, required_version: str) -> bool:
    def to_numbers(version: str) -> List[int]:
        return [int(part) for part in version.split(".")]
    return to_numbers(installed_version) >= to_numbers(required_version)


def read_installed_emacs_version(prefix: Path) -> Optional[str]:
    emacs_path = prefix / "bin" / "emacs"
    if not emacs_path.exists():
        return None
    completed = subprocess.run(
        [str(emacs_path), "--batch", "--eval", "(princ emacs-version)"],
        capture_output=True, text=True)
    installed_version = completed.stdout.strip()
    if completed.returncode != 0 or not installed_version:
        return None
    return installed_version


def is_installed_emacs_current(options: argparse.Namespace) -> bool:
    """Return whether the Emacs under the prefix makes a build unnecessary.

    A branch name has no version to compare against, so it always needs a
    build.
    """
    if options.force:
        return False
    required_version = extract_numeric_version(options.version)
    installed_version = read_installed_emacs_version(options.prefix)
    if required_version is None or installed_version is None:
        return False
    return is_version_at_least(installed_version, required_version)


def has_terminal_library(compiler_path: str) -> bool:
    """Return whether the linker finds a library that provides tputs.

    The linker finds one only when the -dev package installs the unversioned
    .so symlink.
    """
    with tempfile.TemporaryDirectory() as work_dir:
        source_path = Path(work_dir) / "probe.c"
        source_path.write_text("int main(void) { return 0; }\n")
        return any(
            succeeds([compiler_path, str(source_path), f"-l{library_name}",
                      "-o", str(Path(work_dir) / "probe")])
            for library_name in ("tinfo", "ncurses", "curses", "termcap"))


def find_c_compiler() -> Optional[str]:
    """Return the path of cc, or of gcc on a host without the cc link."""
    return shutil.which("cc") or shutil.which("gcc")


def list_missing_requirements() -> List[str]:
    """Return the Debian packages of requirements the script cannot build."""
    missing_packages = [
        package_name
        for command_name, package_name in (
            ("git", "git"), ("make", "make"), ("pkg-config", "pkg-config"),
            ("perl", "perl"))
        if shutil.which(command_name) is None]
    compiler_path = find_c_compiler()
    if compiler_path is None:
        missing_packages.insert(0, "gcc")
    elif not has_terminal_library(compiler_path):
        missing_packages.append("libncurses-dev")
    return missing_packages


def prepend_path(env: Dict[str, str], name: str, value: str,
                 separator: str = ":") -> None:
    current_value = env.get(name)
    env[name] = f"{value}{separator}{current_value}" if current_value \
        else value


def build_environment(prefix: Path) -> Dict[str, str]:
    """Return the environment for every build step.

    The tools and libraries built into the prefix become visible to
    configure, and the prefix becomes a runtime search path so that emacs
    finds a tree-sitter installed there.
    """
    env = dict(os.environ)
    prepend_path(env, "PATH", str(prefix / "bin"))
    prepend_path(env, "PKG_CONFIG_PATH", str(prefix / "lib" / "pkgconfig"))
    prepend_path(env, "CPPFLAGS", f"-I{prefix / 'include'}", " ")
    prepend_path(env, "LDFLAGS",
                 f"-L{prefix / 'lib'} -Wl,-rpath,{prefix / 'lib'}", " ")
    # Debian installs libgccjit.so in the private GCC directory, which the
    # linker does not search. libgccjit also reads LIBRARY_PATH at run time
    # to find libgcc when Emacs compiles a .eln file.
    if shutil.which("gcc"):
        libgcc_path = subprocess.run(
            ["gcc", "-print-libgcc-file-name"], capture_output=True,
            text=True, check=True).stdout.strip()
        gcc_library_dir = str(Path(libgcc_path).parent)
        prepend_path(env, "LIBRARY_PATH", gcc_library_dir)
        env["LDFLAGS"] = f"{env['LDFLAGS']} -L{gcc_library_dir}"
    return env


def get_download_cache_dir() -> Path:
    cache_home = os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")
    return Path(cache_home) / "build-emacs"


def fetch_url(url: str, destination: Path) -> None:
    with urllib.request.urlopen(url, timeout=DOWNLOAD_TIMEOUT_SECONDS) \
            as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def compute_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download_verified(url: str, expected_sha256: str,
                      destination: Path) -> None:
    """Download url to destination unless a verified copy is already there.

    Stops the script when the downloaded file has another SHA-256, after
    deleting the file so that the next run downloads it again.
    """
    if destination.is_file() and \
            compute_sha256(destination) == expected_sha256:
        return
    fetch_url(url, destination)
    actual_sha256 = compute_sha256(destination)
    if actual_sha256 != expected_sha256:
        destination.unlink()
        die(f"checksum mismatch for {url}: got {actual_sha256}")


def extract_tarball(archive_path: Path, destination: Path) -> None:
    with tarfile.open(archive_path) as archive:
        # The data filter rejects absolute paths and links that escape the
        # destination. Python releases before 3.12 lack it.
        if hasattr(tarfile, "data_filter"):
            archive.extractall(destination, filter="data")
        else:
            archive.extractall(destination)


def install_gnu_package(release: GnuRelease, prefix: Path, jobs: int,
                        env: Dict[str, str]) -> None:
    """Build a GNU package from its release tarball into prefix."""
    cache_dir = get_download_cache_dir()
    cache_dir.mkdir(parents=True, exist_ok=True)
    archive_name = f"{release.name}-{release.version}.tar.xz"
    archive_path = cache_dir / archive_name
    log(f"Building {release.name} {release.version} into {prefix}")
    download_verified(f"{GNU_MIRROR_URL}/{release.name}/{archive_name}",
                      release.sha256, archive_path)
    source_dir = cache_dir / f"{release.name}-{release.version}"
    shutil.rmtree(source_dir, ignore_errors=True)
    extract_tarball(archive_path, cache_dir)
    run(["./configure", f"--prefix={prefix}"], cwd=source_dir, env=env)
    run(["make", "-j", str(jobs)], cwd=source_dir, env=env)
    run(["make", "install"], cwd=source_dir, env=env)


def ensure_build_tools(prefix: Path, jobs: int, env: Dict[str, str]) -> None:
    """Build m4, autoconf, and makeinfo into prefix when they are missing.

    autoconf runs m4, and Emacs's autogen.sh requires autoconf. A checkout
    from git carries no prebuilt manuals, so configure requires makeinfo.
    """
    for command_name, release in (("m4", GNU_M4),
                                  ("autoconf", GNU_AUTOCONF),
                                  ("makeinfo", GNU_TEXINFO)):
        if shutil.which(command_name, path=env["PATH"]) is None:
            install_gnu_package(release, prefix, jobs, env)


def read_head_commit(repository: Path) -> str:
    return subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True).stdout.strip()


def ensure_tree_sitter(prefix: Path, jobs: int, env: Dict[str, str]) -> None:
    if succeeds(["pkg-config", "--exists", "tree-sitter"], env=env):
        return
    tree_sitter_dir = get_download_cache_dir() / \
        f"tree-sitter-{TREE_SITTER_VERSION}"
    log(f"Building tree-sitter {TREE_SITTER_VERSION} into {prefix}")
    if not tree_sitter_dir.is_dir():
        run(["git", "clone", "--depth", "1", "--branch", TREE_SITTER_VERSION,
             TREE_SITTER_REPOSITORY_URL, str(tree_sitter_dir)])
    head_commit = read_head_commit(tree_sitter_dir)
    if head_commit != TREE_SITTER_COMMIT:
        die(f"{tree_sitter_dir} is at {head_commit}, not the pinned "
            f"{TREE_SITTER_COMMIT}. Remove the directory and rerun.")
    run(["make", "-C", str(tree_sitter_dir), "-j", str(jobs),
         f"PREFIX={prefix}"], env=env)
    run(["make", "-C", str(tree_sitter_dir), f"PREFIX={prefix}", "install"],
        env=env)


def checkout_emacs_source(source_dir: Path, version: str) -> None:
    """Fetch version into source_dir and check it out.

    A shallow checkout stays shallow, and a full clone keeps its history.
    """
    if not (source_dir / ".git").is_dir():
        log(f"Cloning {version} into {source_dir}")
        source_dir.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", "--branch", version,
             EMACS_REPOSITORY_URL, str(source_dir)])
        return
    is_shallow = subprocess.run(
        ["git", "-C", str(source_dir), "rev-parse",
         "--is-shallow-repository"],
        capture_output=True, text=True, check=True).stdout.strip() == "true"
    depth_arguments = ["--depth", "1"] if is_shallow else []
    log(f"Checking out {version} in {source_dir}")
    run(["git", "-C", str(source_dir), "fetch", *depth_arguments, "origin",
         version])
    run(["git", "-C", str(source_dir), "checkout", "--detach", "FETCH_HEAD"])


def clean_stale_build_tree(source_dir: Path, version: str) -> None:
    """Remove build artifacts that another Emacs version left in the tree.

    make reuses the .elc and .eln files left in the tree. Artifacts from
    another version make the native compiler load a stale .eln and abort
    with "Recursive load". The stamp is written before the build, so a build
    that dies halfway resumes incrementally instead of cleaning again.
    """
    stamp_path = source_dir / BUILD_STAMP_NAME
    built_version = stamp_path.read_text().strip() \
        if stamp_path.exists() else None
    if built_version == version:
        return
    log(f"Removing build artifacts that do not belong to {version}")
    run(["git", "-C", str(source_dir), "clean", "-xdf"])
    stamp_path.write_text(f"{version}\n")


def has_gtk3(env: Dict[str, str]) -> bool:
    return succeeds(["pkg-config", "--exists", "gtk+-3.0"], env=env)


def has_usable_libgccjit(env: Dict[str, str]) -> bool:
    """Return whether gcc links a program against libgccjit.

    libgccjit ships no pkg-config file, and Debian installs the .so in the
    private GCC directory. Only a link probe with the LIBRARY_PATH and
    LDFLAGS from build_environment tells whether Emacs can use it.
    """
    with tempfile.TemporaryDirectory() as work_dir:
        source_path = Path(work_dir) / "probe.c"
        source_path.write_text(
            "#include <libgccjit.h>\n"
            "int main(void) { return gcc_jit_context_acquire() == 0; }\n")
        return succeeds(["gcc", str(source_path), "-lgccjit",
                         "-o", str(Path(work_dir) / "probe")], env=env)


def has_sqlite3(env: Dict[str, str]) -> bool:
    with tempfile.TemporaryDirectory() as work_dir:
        source_path = Path(work_dir) / "probe.c"
        source_path.write_text(
            "#include <sqlite3.h>\n"
            "int main(void) { return sqlite3_libversion_number() == 0; }\n")
        return succeeds([find_c_compiler() or "cc", str(source_path),
                         "-lsqlite3",
                         "-o", str(Path(work_dir) / "probe")], env=env)


def assert_required_features(options: argparse.Namespace,
                             env: Dict[str, str]) -> None:
    """Stop when a feature requested as required has no library.

    configure drops SQLite without an error even for --with-sqlite3=yes, so
    the script probes for the library itself before building.
    """
    if options.sqlite == "yes" and not has_sqlite3(env):
        die("SQLite was required, but sqlite3.h or libsqlite3 is missing. "
            "Install libsqlite3-dev.")


def build_configure_arguments(options: argparse.Namespace,
                              env: Dict[str, str]) -> List[str]:
    """Return the configure arguments.

    A feature left on "auto" uses "ifavailable" or a probe, so configure
    drops it when its library is missing on a host without root. An explicit
    request makes configure fail instead.
    """
    gnutls_mode = "ifavailable" if options.gnutls == "auto" else "yes"
    arguments = [f"--prefix={options.prefix}", "--with-tree-sitter",
                 f"--with-gnutls={gnutls_mode}", "--without-compress-install"]
    gui_mode = options.gui
    if gui_mode == "auto":
        gui_mode = "pgtk" if has_gtk3(env) else "none"
    if gui_mode == "none":
        arguments.append("--without-x")
    else:
        arguments.append("--with-pgtk")
    if gui_mode == "pgtk" and options.gui == "auto":
        arguments += [f"--with-{image_format}=ifavailable"
                      for image_format in ("xpm", "jpeg", "png", "gif",
                                           "tiff")]
    native_compilation = options.native_compilation
    if native_compilation == "auto":
        native_compilation = "aot" if has_usable_libgccjit(env) else "no"
    arguments.append(f"--with-native-compilation={native_compilation}")
    return arguments


def build_make_variables() -> List[str]:
    """Return make variables that route the compiler through ccache.

    list_missing_requirements accepts a host with cc alone, so the wrapper
    falls back to cc when gcc is missing.
    """
    if shutil.which("ccache") is None:
        return []
    compiler_name = "gcc" if shutil.which("gcc") else "cc"
    return [f"CC=ccache {compiler_name}"]


def build_and_install_emacs(options: argparse.Namespace,
                            env: Dict[str, str]) -> None:
    configure_arguments = build_configure_arguments(options, env)
    make_variables = build_make_variables()
    log(f"Configuring Emacs: {' '.join(configure_arguments)}")
    run(["./autogen.sh"], cwd=options.source_dir, env=env)
    run(["./configure", *configure_arguments], cwd=options.source_dir,
        env=env)
    run(["make", *make_variables, "-j", str(options.jobs)],
        cwd=options.source_dir, env=env)
    run(["make", "install"], cwd=options.source_dir, env=env)


def warn_about_missing_features(prefix: Path) -> None:
    emacs_features = subprocess.run(
        [str(prefix / "bin" / "emacs"), "--batch", "--eval",
         "(princ system-configuration-features)"],
        capture_output=True, text=True, check=True).stdout.split()
    log(f"Installed {prefix / 'bin' / 'emacs'} with: "
        f"{' '.join(emacs_features)}")
    if "GNUTLS" not in emacs_features:
        warn("no GnuTLS: package.el cannot reach https archives. "
             "Install libgnutls28-dev to enable it.")
    if "SQLITE3" not in emacs_features:
        warn("no SQLite: org-roam and other emacsql users cannot open "
             "databases. Install libsqlite3-dev to enable it.")
    if "NATIVE_COMP" not in emacs_features:
        warn("no native compilation. "
             "Install libgccjit-<gcc version>-dev to enable it.")


def main(argv: List[str]) -> int:
    options = parse_arguments(argv)
    if is_installed_emacs_current(options):
        log(f"Emacs under {options.prefix} is already {options.version} "
            f"or newer")
        return 0
    if options.check:
        return EXIT_CODE_BUILD_NEEDED
    missing_packages = list_missing_requirements()
    if missing_packages:
        die("missing requirements. Ask an administrator to install: "
            f"{' '.join(missing_packages)}")
    env = build_environment(options.prefix)
    ensure_build_tools(options.prefix, options.jobs, env)
    ensure_tree_sitter(options.prefix, options.jobs, env)
    assert_required_features(options, env)
    checkout_emacs_source(options.source_dir, options.version)
    clean_stale_build_tree(options.source_dir, options.version)
    build_and_install_emacs(options, env)
    warn_about_missing_features(options.prefix)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except subprocess.CalledProcessError as error:
        die(f"command failed with status {error.returncode}: "
            f"{' '.join(map(str, error.cmd))}")
    except OSError as error:
        # URLError and socket timeouts from a download are OSError too.
        die(str(error))
