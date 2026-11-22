#!/usr/bin/env python3
"""Check known vulnerabilities (CVE / GHSA) for dependency versions.

The script queries the OSV database (https://osv.dev), which aggregates the
GitHub Advisory Database, NVD, and others. It uses only the Python standard
library.

Usage:
  check_cve.py <name>@<version> [...]             # npm packages
  check_cve.py --ecosystem PyPI requests@2.31.0   # any OSV ecosystem
  check_cve.py --git <base-ref> <head-ref>        # every npm package and
                                                  # GitHub Action whose
                                                  # version changed

Options:
  --json    Print machine-readable JSON instead of a text report.

Exit codes: 0 = no known vulnerabilities, 1 = vulnerabilities found,
2 = usage or network error.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Callable, Protocol, Sequence

OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
OSV_VULNERABILITY_URL = "https://api.osv.dev/v1/vulns/"
OSV_PAGE_URL = "https://osv.dev/vulnerability/"
BATCH_SIZE = 500
REQUEST_TIMEOUT_SECONDS = 30

# Above this many findings, the text report hides the rows without a finding.
MAX_LISTED_CLEAN_FINDINGS = 30

NPM_ECOSYSTEM = "npm"
GITHUB_ACTIONS_ECOSYSTEM = "GitHub Actions"
WORKFLOW_DIRECTORY = ".github/workflows"

# The version is the ref (`@v4.2.0`) or, for a SHA pin, the trailing comment
# (`@<sha> # v4.2.0`). The comment part uses [ \t] so that a comment on the
# next line never attaches to a pin that has none.
WORKFLOW_USES_PATTERN = re.compile(
    r"""uses:\s*['"]?([\w.-]+/[\w.-]+)(?:/[^@\s'"]*)?@([^\s'"#]+)['"]?"""
    r"""(?:[ \t]*#[ \t]*(\S+))?"""
)
FULL_SHA_PATTERN = re.compile(r"^[0-9a-f]{40}$")
VERSION_PATTERN = re.compile(r"^\d+(\.\d+){0,2}")

# Maps a package name to every version of it that a file mentions.
VersionMap = dict[str, set[str]]


class ExitStatus(Enum):
    CLEAN = 0
    VULNERABLE = 1
    ERROR = 2


class CheckCveError(Exception):
    """A usage, git, or network failure; main() prints it and exits with 2."""


@dataclass(frozen=True)
class PackageVersion:
    ecosystem: str
    name: str
    version: str
    previous_versions: tuple[str, ...]


@dataclass(frozen=True)
class OsvAffectedPackage:
    name: str
    ecosystem_severity: str
    fixed_versions: tuple[str, ...]


@dataclass(frozen=True)
class OsvVulnerability:
    """The parts of an OSV vulnerability record that the report needs.

    Missing text fields are empty strings, and `score_severity` is the first
    entry of the record's `severity` list.
    """

    id: str
    aliases: tuple[str, ...]
    withdrawn: bool
    summary: str
    database_severity: str
    score_severity: str
    affected: tuple[OsvAffectedPackage, ...]


@dataclass(frozen=True)
class Advisory:
    id: str
    aliases: tuple[str, ...]
    severity: str
    summary: str
    fixed_versions: tuple[str, ...]
    url: str


@dataclass(frozen=True)
class Finding:
    package: PackageVersion
    advisories: tuple[Advisory, ...]


class OsvClient(Protocol):
    def query_batch(
        self, packages: Sequence[PackageVersion]
    ) -> list[tuple[str, ...]]:
        """Return the vulnerability IDs of each package, in input order."""
        ...

    def fetch_vulnerability(self, vulnerability_id: str) -> OsvVulnerability:
        ...


class Repository(Protocol):
    def verify_ref(self, ref: str) -> None:
        """Raise CheckCveError unless the ref names a commit."""
        ...

    def read_file(self, ref: str, path: str) -> str:
        """Return the file content at the ref, or "" when the file is absent."""
        ...

    def list_workflow_files(self, ref: str) -> list[str]:
        ...


@dataclass(frozen=True)
class LockfileSource:
    """A lockfile at the repository root and the function that parses it.

    Support for another lockfile format needs one parse function and one entry
    in LOCKFILE_SOURCES.
    """

    ecosystem: str
    path: str
    parse: Callable[[str], VersionMap]


def as_object(value: object) -> dict[str, object]:
    return value if isinstance(value, dict) else {}


def as_list(value: object) -> list[object]:
    return value if isinstance(value, list) else []


def as_text(value: object) -> str:
    return value if isinstance(value, str) else ""


def parse_package_spec(spec: str, ecosystem: str) -> PackageVersion:
    # Split on the last '@' so that a scoped name (@scope/name@1.0.0) works.
    separator_index = spec.rfind("@")
    if separator_index <= 0 or separator_index == len(spec) - 1:
        raise CheckCveError(f'invalid spec "{spec}", expected <name>@<version>')
    return PackageVersion(
        ecosystem=ecosystem,
        name=spec[:separator_index],
        version=spec[separator_index + 1 :],
        previous_versions=(),
    )


def extract_package_name_from_lock_path(path: str) -> str:
    marker = "node_modules/"
    marker_index = path.rfind(marker)
    return "" if marker_index < 0 else path[marker_index + len(marker) :]


def parse_lockfile(text: str) -> VersionMap:
    """Read a package-lock.json (lockfileVersion 2 or 3) into a VersionMap."""
    if not text.strip():
        return {}
    try:
        lock = json.loads(text)
    except json.JSONDecodeError as error:
        raise CheckCveError(f"invalid package-lock.json: {error}") from error
    versions: VersionMap = {}
    for path, raw_info in as_object(as_object(lock).get("packages")).items():
        info = as_object(raw_info)
        version = as_text(info.get("version"))
        name = as_text(info.get("name")) or extract_package_name_from_lock_path(path)
        if not path or not version or not name or info.get("link"):
            continue
        versions.setdefault(name, set()).add(version)
    return versions


def parse_workflow_actions(text: str) -> VersionMap:
    """Read the `uses:` lines of a workflow file into a VersionMap."""
    versions: VersionMap = {}
    for match in WORKFLOW_USES_PATTERN.finditer(text):
        name, git_ref, comment = match.groups()
        raw_version = comment if FULL_SHA_PATTERN.match(git_ref) else git_ref
        if not raw_version:
            continue
        version = raw_version.removeprefix("v")
        if VERSION_PATTERN.match(version):
            versions.setdefault(name, set()).add(version)
    return versions


def merge_version_maps(version_maps: Sequence[VersionMap]) -> VersionMap:
    merged: VersionMap = {}
    for version_map in version_maps:
        for name, versions in version_map.items():
            merged.setdefault(name, set()).update(versions)
    return merged


def find_changed_packages(
    base: VersionMap, head: VersionMap, ecosystem: str
) -> list[PackageVersion]:
    """List the versions in head that base lacks, with the base versions."""
    changed: list[PackageVersion] = []
    for name, head_versions in head.items():
        previous_versions = tuple(sorted(base.get(name, set())))
        for version in sorted(head_versions):
            if version in previous_versions:
                continue
            changed.append(
                PackageVersion(ecosystem, name, version, previous_versions)
            )
    return changed


LOCKFILE_SOURCES = (
    LockfileSource(NPM_ECOSYSTEM, "package-lock.json", parse_lockfile),
)


def read_workflow_actions(repository: Repository, ref: str) -> VersionMap:
    return merge_version_maps(
        [
            parse_workflow_actions(repository.read_file(ref, path))
            for path in repository.list_workflow_files(ref)
        ]
    )


def collect_changed_packages(
    repository: Repository, base_ref: str, head_ref: str
) -> list[PackageVersion]:
    repository.verify_ref(base_ref)
    repository.verify_ref(head_ref)
    changed: list[PackageVersion] = []
    for source in LOCKFILE_SOURCES:
        changed.extend(
            find_changed_packages(
                source.parse(repository.read_file(base_ref, source.path)),
                source.parse(repository.read_file(head_ref, source.path)),
                source.ecosystem,
            )
        )
    changed.extend(
        find_changed_packages(
            read_workflow_actions(repository, base_ref),
            read_workflow_actions(repository, head_ref),
            GITHUB_ACTIONS_ECOSYSTEM,
        )
    )
    return changed


def parse_affected_package(raw: object) -> OsvAffectedPackage:
    affected = as_object(raw)
    fixed_versions = [
        as_text(as_object(event).get("fixed"))
        for version_range in as_list(affected.get("ranges"))
        for event in as_list(as_object(version_range).get("events"))
    ]
    return OsvAffectedPackage(
        name=as_text(as_object(affected.get("package")).get("name")),
        ecosystem_severity=as_text(
            as_object(affected.get("ecosystem_specific")).get("severity")
        ),
        fixed_versions=tuple(dict.fromkeys(v for v in fixed_versions if v)),
    )


def parse_vulnerability(raw: object) -> OsvVulnerability:
    """Parse an OSV vulnerability JSON object at the network boundary."""
    record = as_object(raw)
    vulnerability_id = as_text(record.get("id"))
    if not vulnerability_id:
        raise CheckCveError("OSV returned a vulnerability without an id")
    scores = as_list(record.get("severity"))
    return OsvVulnerability(
        id=vulnerability_id,
        aliases=tuple(as_text(alias) for alias in as_list(record.get("aliases"))),
        withdrawn=bool(record.get("withdrawn")),
        summary=as_text(record.get("summary")),
        database_severity=as_text(
            as_object(record.get("database_specific")).get("severity")
        ),
        score_severity=as_text(as_object(scores[0]).get("score")) if scores else "",
        affected=tuple(
            parse_affected_package(item) for item in as_list(record.get("affected"))
        ),
    )


def extract_severity(vulnerability: OsvVulnerability) -> str:
    ecosystem_severity = next(
        (a.ecosystem_severity for a in vulnerability.affected if a.ecosystem_severity),
        "",
    )
    return (
        vulnerability.database_severity
        or ecosystem_severity
        or vulnerability.score_severity
        or "UNKNOWN"
    )


def extract_fixed_versions(
    vulnerability: OsvVulnerability, package_name: str
) -> tuple[str, ...]:
    fixed_versions = [
        version
        for affected in vulnerability.affected
        if affected.name == package_name
        for version in affected.fixed_versions
    ]
    return tuple(dict.fromkeys(fixed_versions))


def build_advisory(
    vulnerability: OsvVulnerability, package: PackageVersion
) -> Advisory:
    return Advisory(
        id=vulnerability.id,
        aliases=vulnerability.aliases,
        severity=extract_severity(vulnerability),
        summary=vulnerability.summary,
        fixed_versions=extract_fixed_versions(vulnerability, package.name),
        url=OSV_PAGE_URL + vulnerability.id,
    )


def query_vulnerability_ids(
    packages: Sequence[PackageVersion], client: OsvClient, batch_size: int
) -> list[tuple[str, ...]]:
    ids_per_package: list[tuple[str, ...]] = []
    for start in range(0, len(packages), batch_size):
        ids_per_package.extend(client.query_batch(packages[start : start + batch_size]))
    return ids_per_package


def check_packages(
    packages: Sequence[PackageVersion],
    client: OsvClient,
    batch_size: int = BATCH_SIZE,
) -> list[Finding]:
    """Look up every package in OSV and return one Finding per package."""
    ids_per_package = query_vulnerability_ids(packages, client, batch_size)
    cache: dict[str, OsvVulnerability] = {}
    findings: list[Finding] = []
    for package, vulnerability_ids in zip(packages, ids_per_package):
        advisories: list[Advisory] = []
        for vulnerability_id in vulnerability_ids:
            if vulnerability_id not in cache:
                cache[vulnerability_id] = client.fetch_vulnerability(vulnerability_id)
            vulnerability = cache[vulnerability_id]
            if not vulnerability.withdrawn:
                advisories.append(build_advisory(vulnerability, package))
        findings.append(Finding(package, tuple(advisories)))
    return findings


def has_advisories(finding: Finding) -> bool:
    return len(finding.advisories) > 0


def decide_exit_status(findings: Sequence[Finding]) -> ExitStatus:
    if any(has_advisories(finding) for finding in findings):
        return ExitStatus.VULNERABLE
    return ExitStatus.CLEAN


def render_advisory_lines(advisory: Advisory) -> list[str]:
    cve_ids = ", ".join(a for a in advisory.aliases if a.startswith("CVE-"))
    cve_suffix = f" ({cve_ids})" if cve_ids else ""
    fixed = ", ".join(advisory.fixed_versions) or "no fix available"
    return [
        f"      - {advisory.id}{cve_suffix} [{advisory.severity}] {advisory.summary}",
        f"        fixed in: {fixed}  {advisory.url}",
    ]


def render_finding_lines(finding: Finding, is_clean_row_listed: bool) -> list[str]:
    if not has_advisories(finding) and not is_clean_row_listed:
        return []
    package = finding.package
    previous = ", ".join(package.previous_versions)
    arrow = f"{previous} -> " if previous else ""
    status = (
        f"VULNERABLE ({len(finding.advisories)})" if has_advisories(finding) else "ok"
    )
    lines = [f"  [{package.ecosystem}] {package.name} {arrow}{package.version}: {status}"]
    for advisory in finding.advisories:
        lines.extend(render_advisory_lines(advisory))
    return lines


def render_text_report(findings: Sequence[Finding]) -> str:
    if not findings:
        return "No changed dependency versions to check."
    vulnerable_count = sum(1 for finding in findings if has_advisories(finding))
    is_clean_row_listed = len(findings) <= MAX_LISTED_CLEAN_FINDINGS
    lines = [f"Checked {len(findings)} package version(s) against OSV."]
    for finding in findings:
        lines.extend(render_finding_lines(finding, is_clean_row_listed))
    if not is_clean_row_listed:
        omitted_count = len(findings) - vulnerable_count
        lines.append(f"  ({omitted_count} package(s) without findings omitted)")
    lines.append(
        f"RESULT: {vulnerable_count} package version(s) have known vulnerabilities."
        if vulnerable_count
        else "RESULT: no known vulnerabilities."
    )
    return "\n".join(lines)


def render_json_report(findings: Sequence[Finding]) -> str:
    return json.dumps(
        [
            {
                "ecosystem": finding.package.ecosystem,
                "name": finding.package.name,
                "version": finding.package.version,
                "from": ", ".join(finding.package.previous_versions) or None,
                "vulns": [
                    {
                        "id": advisory.id,
                        "aliases": list(advisory.aliases),
                        "severity": advisory.severity,
                        "summary": advisory.summary,
                        "fixed": list(advisory.fixed_versions),
                        "url": advisory.url,
                    }
                    for advisory in finding.advisories
                ],
            }
            for finding in findings
        ],
        indent=2,
    )


class HttpOsvClient:
    """Talk to api.osv.dev. This is the only code that touches the network."""

    def query_batch(
        self, packages: Sequence[PackageVersion]
    ) -> list[tuple[str, ...]]:
        payload = {
            "queries": [
                {
                    "package": {"name": p.name, "ecosystem": p.ecosystem},
                    "version": p.version,
                }
                for p in packages
            ]
        }
        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            OSV_BATCH_URL,
            data=body,
            headers={"content-type": "application/json"},
            method="POST",
        )
        results = as_list(as_object(self.send(request)).get("results"))
        if len(results) != len(packages):
            raise CheckCveError(f"{OSV_BATCH_URL}: unexpected number of results")
        return [
            tuple(
                as_text(as_object(vulnerability).get("id"))
                for vulnerability in as_list(as_object(result).get("vulns"))
            )
            for result in results
        ]

    def fetch_vulnerability(self, vulnerability_id: str) -> OsvVulnerability:
        quoted_id = urllib.parse.quote(vulnerability_id, safe="")
        request = urllib.request.Request(OSV_VULNERABILITY_URL + quoted_id)
        return parse_vulnerability(self.send(request))

    def send(self, request: urllib.request.Request) -> object:
        try:
            with urllib.request.urlopen(
                request, timeout=REQUEST_TIMEOUT_SECONDS
            ) as response:
                return json.load(response)
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            raise CheckCveError(f"{request.full_url}: {error}") from error


class GitRepository:
    """Read files from git objects with the git CLI, in a given directory."""

    def __init__(self, root: Path) -> None:
        self.root = root

    def run_git(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )

    def verify_ref(self, ref: str) -> None:
        # A leading '-' would make git read the ref as an option.
        if ref.startswith("-"):
            raise CheckCveError(f"invalid git ref: {ref}")
        result = self.run_git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
        if result.returncode != 0:
            raise CheckCveError(f"unknown git ref: {ref}")

    def read_file(self, ref: str, path: str) -> str:
        result = self.run_git("show", f"{ref}:{path}")
        return result.stdout if result.returncode == 0 else ""

    def list_workflow_files(self, ref: str) -> list[str]:
        result = self.run_git(
            "ls-tree", "-r", "--name-only", ref, "--", WORKFLOW_DIRECTORY
        )
        if result.returncode != 0:
            return []
        return [
            line
            for line in result.stdout.splitlines()
            if line.endswith((".yml", ".yaml"))
        ]


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="check_cve.py",
        description="Check dependency versions against the OSV database.",
        epilog="Exit codes: 0 = clean, 1 = vulnerabilities found, 2 = error.",
    )
    parser.add_argument("packages", nargs="*", metavar="NAME@VERSION")
    parser.add_argument(
        "--ecosystem",
        default=NPM_ECOSYSTEM,
        help="OSV ecosystem of the NAME@VERSION arguments (default: npm)",
    )
    parser.add_argument(
        "--git",
        nargs=2,
        metavar=("BASE_REF", "HEAD_REF"),
        help="check every npm and GitHub Actions version that is new in HEAD_REF",
    )
    parser.add_argument("--json", action="store_true", help="print JSON")
    return parser


def run(
    argv: Sequence[str], client: OsvClient, repository: Repository
) -> ExitStatus:
    parser = build_argument_parser()
    arguments = parser.parse_args(argv)
    if bool(arguments.git) == bool(arguments.packages):
        parser.error("give either NAME@VERSION arguments or --git, not both or none")
    if arguments.git:
        base_ref, head_ref = arguments.git
        packages = collect_changed_packages(repository, base_ref, head_ref)
    else:
        packages = [
            parse_package_spec(spec, arguments.ecosystem)
            for spec in arguments.packages
        ]
    findings = check_packages(packages, client)
    report = (
        render_json_report(findings)
        if arguments.json
        else render_text_report(findings)
    )
    print(report)
    return decide_exit_status(findings)


def main(argv: Sequence[str]) -> ExitStatus:
    try:
        return run(argv, HttpOsvClient(), GitRepository(Path.cwd()))
    except CheckCveError as error:
        print(f"error: {error}", file=sys.stderr)
        return ExitStatus.ERROR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]).value)
