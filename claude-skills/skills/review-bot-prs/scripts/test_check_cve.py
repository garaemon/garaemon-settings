"""Tests for check_cve.py.

A fake OSV client and a fake repository replace the network and git, so the
tests need neither. Only GitRepositoryTest runs real git, in a temporary
repository.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Sequence

import check_cve
from check_cve import (
    Advisory,
    CheckCveError,
    ExitStatus,
    Finding,
    OsvAffectedPackage,
    OsvVulnerability,
    PackageVersion,
)


def build_vulnerability(
    vulnerability_id: str = "GHSA-aaaa-bbbb-cccc",
    aliases: Sequence[str] = (),
    withdrawn: bool = False,
    summary: str = "Example flaw",
    fixed_versions: Sequence[str] = ("2.0.0",),
    package_name: str = "left-pad",
) -> OsvVulnerability:
    return OsvVulnerability(
        id=vulnerability_id,
        aliases=tuple(aliases),
        withdrawn=withdrawn,
        summary=summary,
        database_severity="HIGH",
        score_severity="",
        affected=(
            OsvAffectedPackage(
                name=package_name,
                ecosystem_severity="",
                fixed_versions=tuple(fixed_versions),
            ),
        ),
    )


def build_package(
    name: str = "left-pad",
    version: str = "1.0.0",
    ecosystem: str = "npm",
    previous_versions: Sequence[str] = (),
) -> PackageVersion:
    return PackageVersion(
        ecosystem=ecosystem,
        name=name,
        version=version,
        previous_versions=tuple(previous_versions),
    )


class FakeOsvClient:
    def __init__(
        self,
        ids_by_package: dict[str, Sequence[str]] | None = None,
        vulnerabilities: dict[str, OsvVulnerability] | None = None,
    ) -> None:
        self.ids_by_package = ids_by_package or {}
        self.vulnerabilities = vulnerabilities or {}
        self.batch_sizes: list[int] = []
        self.queried_ecosystems: list[str] = []
        self.fetched_ids: list[str] = []

    def query_batch(
        self, packages: Sequence[PackageVersion]
    ) -> list[tuple[str, ...]]:
        self.batch_sizes.append(len(packages))
        self.queried_ecosystems.extend(p.ecosystem for p in packages)
        return [
            tuple(self.ids_by_package.get(f"{p.name}@{p.version}", ()))
            for p in packages
        ]

    def fetch_vulnerability(self, vulnerability_id: str) -> OsvVulnerability:
        self.fetched_ids.append(vulnerability_id)
        return self.vulnerabilities[vulnerability_id]


class FakeRepository:
    def __init__(
        self,
        files_by_ref: dict[str, dict[str, str]] | None = None,
    ) -> None:
        self.files_by_ref = files_by_ref or {}

    def verify_ref(self, ref: str) -> None:
        if ref not in self.files_by_ref:
            raise CheckCveError(f"unknown git ref: {ref}")

    def read_file(self, ref: str, path: str) -> str:
        return self.files_by_ref[ref].get(path, "")

    def list_workflow_files(self, ref: str) -> list[str]:
        return sorted(
            path
            for path in self.files_by_ref[ref]
            if path.startswith(".github/workflows/")
        )


def build_lockfile(packages: dict[str, dict[str, object]]) -> str:
    return json.dumps({"lockfileVersion": 3, "packages": packages})


class ParseLockfileTest(unittest.TestCase):
    def test_should_map_package_name_to_versions(self) -> None:
        text = build_lockfile({"node_modules/a": {"version": "1.0.0"}})
        self.assertEqual(check_cve.parse_lockfile(text), {"a": {"1.0.0"}})

    def test_should_skip_root_entry(self) -> None:
        text = build_lockfile({"": {"name": "app", "version": "0.1.0"}})
        self.assertEqual(check_cve.parse_lockfile(text), {})

    def test_should_skip_link_entries(self) -> None:
        text = build_lockfile(
            {"node_modules/a": {"resolved": "packages/a", "link": True}}
        )
        self.assertEqual(check_cve.parse_lockfile(text), {})

    def test_should_use_last_node_modules_segment_for_nested_paths(self) -> None:
        text = build_lockfile(
            {"node_modules/a/node_modules/@s/b": {"version": "2.0.0"}}
        )
        self.assertEqual(check_cve.parse_lockfile(text), {"@s/b": {"2.0.0"}})

    def test_should_prefer_name_field_over_path(self) -> None:
        text = build_lockfile(
            {"node_modules/alias": {"name": "real", "version": "1.0.0"}}
        )
        self.assertEqual(check_cve.parse_lockfile(text), {"real": {"1.0.0"}})

    def test_should_collect_several_versions_of_one_package(self) -> None:
        text = build_lockfile(
            {
                "node_modules/a": {"version": "1.0.0"},
                "node_modules/x/node_modules/a": {"version": "2.0.0"},
            }
        )
        self.assertEqual(
            check_cve.parse_lockfile(text), {"a": {"1.0.0", "2.0.0"}}
        )

    def test_should_return_empty_map_for_empty_text(self) -> None:
        self.assertEqual(check_cve.parse_lockfile(""), {})

    def test_should_return_empty_map_for_lockfile_without_packages(self) -> None:
        text = json.dumps({"lockfileVersion": 1, "dependencies": {}})
        self.assertEqual(check_cve.parse_lockfile(text), {})

    def test_should_raise_for_invalid_json(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_lockfile("{not json")


class ParseWorkflowActionsTest(unittest.TestCase):
    def test_should_read_version_from_tag_ref(self) -> None:
        text = "      - uses: actions/checkout@v4.2.0\n"
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/checkout": {"4.2.0"}},
        )

    def test_should_read_version_from_comment_of_sha_pin(self) -> None:
        sha = "a" * 40
        text = f"      - uses: actions/checkout@{sha} # v4.2.0\n"
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/checkout": {"4.2.0"}},
        )

    def test_should_skip_sha_pin_without_comment(self) -> None:
        sha = "b" * 40
        text = f"      - uses: actions/checkout@{sha}\n"
        self.assertEqual(check_cve.parse_workflow_actions(text), {})

    def test_should_read_quoted_value(self) -> None:
        text = "      - uses: 'actions/setup-node@v4.1.0'\n"
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/setup-node": {"4.1.0"}},
        )

    def test_should_read_double_quoted_value_with_comment_pin(self) -> None:
        sha = "c" * 40
        text = f'      - uses: "actions/cache@{sha}" # v3.3.1\n'
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/cache": {"3.3.1"}},
        )

    def test_should_drop_sub_path_from_action_name(self) -> None:
        text = "      - uses: github/codeql-action/analyze@v3.25.0\n"
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"github/codeql-action": {"3.25.0"}},
        )

    def test_should_not_take_comment_of_next_line_for_sha_pin(self) -> None:
        sha = "d" * 40
        text = f"      - uses: actions/checkout@{sha}\n# v9.9.9 unrelated\n"
        self.assertEqual(check_cve.parse_workflow_actions(text), {})

    def test_should_skip_branch_ref(self) -> None:
        text = "      - uses: owner/repo@main\n"
        self.assertEqual(check_cve.parse_workflow_actions(text), {})

    def test_should_skip_local_action(self) -> None:
        text = "      - uses: ./.github/actions/setup\n"
        self.assertEqual(check_cve.parse_workflow_actions(text), {})

    def test_should_accept_major_only_tag(self) -> None:
        text = "      - uses: actions/checkout@v4\n"
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/checkout": {"4"}},
        )

    def test_should_collect_versions_across_lines(self) -> None:
        text = (
            "      - uses: actions/checkout@v4.2.0\n"
            "      - uses: actions/checkout@v3.6.0\n"
        )
        self.assertEqual(
            check_cve.parse_workflow_actions(text),
            {"actions/checkout": {"4.2.0", "3.6.0"}},
        )


class FindChangedPackagesTest(unittest.TestCase):
    def test_should_report_version_that_is_new_in_head(self) -> None:
        changed = check_cve.find_changed_packages(
            {"a": {"1.0.0"}}, {"a": {"1.1.0"}}, "npm"
        )
        self.assertEqual(
            changed, [build_package("a", "1.1.0", previous_versions=("1.0.0",))]
        )

    def test_should_ignore_unchanged_version(self) -> None:
        changed = check_cve.find_changed_packages(
            {"a": {"1.0.0"}}, {"a": {"1.0.0"}}, "npm"
        )
        self.assertEqual(changed, [])

    def test_should_report_new_package_without_previous_versions(self) -> None:
        changed = check_cve.find_changed_packages({}, {"a": {"1.0.0"}}, "npm")
        self.assertEqual(changed, [build_package("a", "1.0.0")])

    def test_should_ignore_package_removed_in_head(self) -> None:
        changed = check_cve.find_changed_packages({"a": {"1.0.0"}}, {}, "npm")
        self.assertEqual(changed, [])

    def test_should_tag_entries_with_ecosystem(self) -> None:
        changed = check_cve.find_changed_packages(
            {}, {"o/r": {"1.0.0"}}, "GitHub Actions"
        )
        self.assertEqual(changed[0].ecosystem, "GitHub Actions")

    def test_should_sort_previous_versions(self) -> None:
        changed = check_cve.find_changed_packages(
            {"a": {"1.2.0", "1.0.0"}}, {"a": {"2.0.0"}}, "npm"
        )
        self.assertEqual(changed[0].previous_versions, ("1.0.0", "1.2.0"))


class ParsePackageSpecTest(unittest.TestCase):
    def test_should_split_name_and_version(self) -> None:
        self.assertEqual(
            check_cve.parse_package_spec("lodash@4.17.20", "npm"),
            build_package("lodash", "4.17.20"),
        )

    def test_should_keep_scope_of_scoped_package(self) -> None:
        self.assertEqual(
            check_cve.parse_package_spec("@scope/name@1.0.0", "npm"),
            build_package("@scope/name", "1.0.0"),
        )

    def test_should_apply_ecosystem(self) -> None:
        package = check_cve.parse_package_spec("requests@2.0.0", "PyPI")
        self.assertEqual(package.ecosystem, "PyPI")

    def test_should_reject_spec_without_version(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_package_spec("lodash", "npm")

    def test_should_reject_scoped_spec_without_version(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_package_spec("@scope/name", "npm")

    def test_should_reject_spec_with_empty_version(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_package_spec("lodash@", "npm")


class ParseVulnerabilityTest(unittest.TestCase):
    def test_should_read_basic_fields(self) -> None:
        vulnerability = check_cve.parse_vulnerability(
            {
                "id": "GHSA-1",
                "aliases": ["CVE-2024-1"],
                "summary": "Bad",
                "database_specific": {"severity": "HIGH"},
            }
        )
        self.assertEqual(
            (vulnerability.id, vulnerability.aliases, vulnerability.summary),
            ("GHSA-1", ("CVE-2024-1",), "Bad"),
        )

    def test_should_default_missing_optional_fields(self) -> None:
        vulnerability = check_cve.parse_vulnerability({"id": "GHSA-1"})
        self.assertEqual(
            (vulnerability.aliases, vulnerability.summary, vulnerability.affected),
            ((), "", ()),
        )

    def test_should_flag_withdrawn_advisory(self) -> None:
        vulnerability = check_cve.parse_vulnerability(
            {"id": "GHSA-1", "withdrawn": "2024-01-01T00:00:00Z"}
        )
        self.assertTrue(vulnerability.withdrawn)

    def test_should_not_flag_advisory_without_withdrawn_field(self) -> None:
        vulnerability = check_cve.parse_vulnerability({"id": "GHSA-1"})
        self.assertFalse(vulnerability.withdrawn)

    def test_should_raise_when_id_is_missing(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_vulnerability({"summary": "no id"})

    def test_should_raise_when_payload_is_not_an_object(self) -> None:
        with self.assertRaises(CheckCveError):
            check_cve.parse_vulnerability(["not", "an", "object"])


class ExtractSeverityTest(unittest.TestCase):
    def test_should_prefer_database_severity(self) -> None:
        vulnerability = check_cve.parse_vulnerability(
            {
                "id": "X",
                "database_specific": {"severity": "CRITICAL"},
                "affected": [
                    {"ecosystem_specific": {"severity": "LOW"}},
                ],
                "severity": [{"score": "CVSS:3.1/AV:N"}],
            }
        )
        self.assertEqual(check_cve.extract_severity(vulnerability), "CRITICAL")

    def test_should_fall_back_to_ecosystem_severity(self) -> None:
        vulnerability = check_cve.parse_vulnerability(
            {
                "id": "X",
                "affected": [
                    {"package": {"name": "p"}},
                    {"ecosystem_specific": {"severity": "MODERATE"}},
                ],
                "severity": [{"score": "CVSS:3.1/AV:N"}],
            }
        )
        self.assertEqual(check_cve.extract_severity(vulnerability), "MODERATE")

    def test_should_fall_back_to_first_score(self) -> None:
        vulnerability = check_cve.parse_vulnerability(
            {"id": "X", "severity": [{"score": "CVSS:3.1/AV:N"}, {"score": "b"}]}
        )
        self.assertEqual(
            check_cve.extract_severity(vulnerability), "CVSS:3.1/AV:N"
        )

    def test_should_report_unknown_when_nothing_is_given(self) -> None:
        vulnerability = check_cve.parse_vulnerability({"id": "X"})
        self.assertEqual(check_cve.extract_severity(vulnerability), "UNKNOWN")


class ExtractFixedVersionsTest(unittest.TestCase):
    RAW = {
        "id": "X",
        "affected": [
            {
                "package": {"name": "left-pad"},
                "ranges": [
                    {
                        "events": [
                            {"introduced": "0"},
                            {"fixed": "1.3.1"},
                            {"fixed": "2.0.1"},
                        ]
                    },
                    {"events": [{"fixed": "1.3.1"}]},
                ],
            },
            {
                "package": {"name": "other"},
                "ranges": [{"events": [{"fixed": "9.9.9"}]}],
            },
        ],
    }

    def test_should_collect_fixed_versions_of_matching_package(self) -> None:
        vulnerability = check_cve.parse_vulnerability(self.RAW)
        self.assertEqual(
            check_cve.extract_fixed_versions(vulnerability, "left-pad"),
            ("1.3.1", "2.0.1"),
        )

    def test_should_return_empty_tuple_when_package_is_unaffected(self) -> None:
        vulnerability = check_cve.parse_vulnerability(self.RAW)
        self.assertEqual(
            check_cve.extract_fixed_versions(vulnerability, "absent"), ()
        )


class CheckPackagesTest(unittest.TestCase):
    def test_should_report_advisory_for_vulnerable_package(self) -> None:
        client = FakeOsvClient(
            {"left-pad@1.0.0": ["GHSA-1"]},
            {"GHSA-1": build_vulnerability("GHSA-1", ["CVE-2024-1"])},
        )
        findings = check_cve.check_packages([build_package()], client)
        self.assertEqual(
            findings[0].advisories,
            (
                Advisory(
                    id="GHSA-1",
                    aliases=("CVE-2024-1",),
                    severity="HIGH",
                    summary="Example flaw",
                    fixed_versions=("2.0.0",),
                    url="https://osv.dev/vulnerability/GHSA-1",
                ),
            ),
        )

    def test_should_return_finding_without_advisories_for_clean_package(self) -> None:
        findings = check_cve.check_packages([build_package()], FakeOsvClient())
        self.assertEqual(findings, [Finding(build_package(), ())])

    def test_should_skip_withdrawn_advisory(self) -> None:
        client = FakeOsvClient(
            {"left-pad@1.0.0": ["GHSA-1"]},
            {"GHSA-1": build_vulnerability("GHSA-1", withdrawn=True)},
        )
        findings = check_cve.check_packages([build_package()], client)
        self.assertEqual(findings[0].advisories, ())

    def test_should_fetch_shared_advisory_once(self) -> None:
        client = FakeOsvClient(
            {"a@1.0.0": ["GHSA-1"], "b@1.0.0": ["GHSA-1"]},
            {"GHSA-1": build_vulnerability("GHSA-1", package_name="a")},
        )
        check_cve.check_packages(
            [build_package("a"), build_package("b")], client
        )
        self.assertEqual(client.fetched_ids, ["GHSA-1"])

    def test_should_split_queries_into_batches(self) -> None:
        client = FakeOsvClient()
        packages = [build_package(f"p{i}") for i in range(5)]
        check_cve.check_packages(packages, client, batch_size=2)
        self.assertEqual(client.batch_sizes, [2, 2, 1])

    def test_should_keep_input_order(self) -> None:
        packages = [build_package(f"p{i}") for i in range(3)]
        findings = check_cve.check_packages(packages, FakeOsvClient(), batch_size=2)
        self.assertEqual([f.package for f in findings], packages)

    def test_should_make_no_request_for_empty_input(self) -> None:
        client = FakeOsvClient()
        check_cve.check_packages([], client)
        self.assertEqual(client.batch_sizes, [])


def build_finding(
    name: str = "left-pad",
    version: str = "1.0.0",
    previous_versions: Sequence[str] = (),
    advisories: Sequence[Advisory] = (),
) -> Finding:
    return Finding(
        build_package(name, version, previous_versions=previous_versions),
        tuple(advisories),
    )


def build_advisory(
    aliases: Sequence[str] = ("CVE-2024-1", "GHSA-x"),
    fixed_versions: Sequence[str] = ("2.0.0",),
) -> Advisory:
    return Advisory(
        id="GHSA-1",
        aliases=tuple(aliases),
        severity="HIGH",
        summary="Example flaw",
        fixed_versions=tuple(fixed_versions),
        url="https://osv.dev/vulnerability/GHSA-1",
    )


class RenderTextReportTest(unittest.TestCase):
    def test_should_say_nothing_to_check_for_empty_findings(self) -> None:
        self.assertEqual(
            check_cve.render_text_report([]),
            "No changed dependency versions to check.",
        )

    def test_should_report_clean_result(self) -> None:
        report = check_cve.render_text_report([build_finding()])
        self.assertEqual(
            report.splitlines(),
            [
                "Checked 1 package version(s) against OSV.",
                "  [npm] left-pad 1.0.0: ok",
                "RESULT: no known vulnerabilities.",
            ],
        )

    def test_should_render_vulnerable_package_with_advisory_details(self) -> None:
        finding = build_finding(
            previous_versions=("0.9.0",), advisories=(build_advisory(),)
        )
        report = check_cve.render_text_report([finding])
        self.assertEqual(
            report.splitlines(),
            [
                "Checked 1 package version(s) against OSV.",
                "  [npm] left-pad 0.9.0 -> 1.0.0: VULNERABLE (1)",
                "      - GHSA-1 (CVE-2024-1) [HIGH] Example flaw",
                "        fixed in: 2.0.0  https://osv.dev/vulnerability/GHSA-1",
                "RESULT: 1 package version(s) have known vulnerabilities.",
            ],
        )

    def test_should_say_no_fix_available_without_fixed_versions(self) -> None:
        finding = build_finding(advisories=(build_advisory(fixed_versions=()),))
        report = check_cve.render_text_report([finding])
        self.assertIn("fixed in: no fix available", report)

    def test_should_omit_cve_parentheses_without_cve_alias(self) -> None:
        finding = build_finding(advisories=(build_advisory(aliases=("GHSA-x",)),))
        report = check_cve.render_text_report([finding])
        self.assertIn("      - GHSA-1 [HIGH] Example flaw", report)

    def test_should_list_clean_rows_up_to_thirty_findings(self) -> None:
        findings = [build_finding(f"p{i}") for i in range(30)]
        report = check_cve.render_text_report(findings)
        self.assertIn("[npm] p29 1.0.0: ok", report)

    def test_should_omit_clean_rows_above_thirty_findings(self) -> None:
        findings = [build_finding(f"p{i}") for i in range(31)]
        report = check_cve.render_text_report(findings)
        self.assertNotIn("p0 1.0.0: ok", report)

    def test_should_keep_vulnerable_rows_above_thirty_findings(self) -> None:
        findings = [build_finding(f"p{i}") for i in range(30)]
        findings.append(build_finding("bad", advisories=(build_advisory(),)))
        report = check_cve.render_text_report(findings)
        self.assertIn("[npm] bad 1.0.0: VULNERABLE (1)", report)

    def test_should_count_omitted_rows_above_thirty_findings(self) -> None:
        findings = [build_finding(f"p{i}") for i in range(31)]
        report = check_cve.render_text_report(findings)
        self.assertIn("(31 package(s) without findings omitted)", report)


class RenderJsonReportTest(unittest.TestCase):
    def test_should_render_empty_list(self) -> None:
        self.assertEqual(json.loads(check_cve.render_json_report([])), [])

    def test_should_render_finding_fields(self) -> None:
        finding = build_finding(
            previous_versions=("0.9.0",), advisories=(build_advisory(),)
        )
        rendered = json.loads(check_cve.render_json_report([finding]))
        self.assertEqual(
            rendered,
            [
                {
                    "ecosystem": "npm",
                    "name": "left-pad",
                    "version": "1.0.0",
                    "from": "0.9.0",
                    "vulns": [
                        {
                            "id": "GHSA-1",
                            "aliases": ["CVE-2024-1", "GHSA-x"],
                            "severity": "HIGH",
                            "summary": "Example flaw",
                            "fixed": ["2.0.0"],
                            "url": "https://osv.dev/vulnerability/GHSA-1",
                        }
                    ],
                }
            ],
        )

    def test_should_render_null_from_for_new_package(self) -> None:
        rendered = json.loads(check_cve.render_json_report([build_finding()]))
        self.assertIsNone(rendered[0]["from"])


class ExitStatusTest(unittest.TestCase):
    def test_should_be_clean_without_findings(self) -> None:
        self.assertEqual(check_cve.decide_exit_status([]), ExitStatus.CLEAN)

    def test_should_be_clean_when_no_advisory_exists(self) -> None:
        self.assertEqual(
            check_cve.decide_exit_status([build_finding()]), ExitStatus.CLEAN
        )

    def test_should_be_vulnerable_when_any_advisory_exists(self) -> None:
        findings = [build_finding(), build_finding(advisories=(build_advisory(),))]
        self.assertEqual(
            check_cve.decide_exit_status(findings), ExitStatus.VULNERABLE
        )

    def test_should_use_documented_exit_codes(self) -> None:
        self.assertEqual(
            [status.value for status in ExitStatus], [0, 1, 2]
        )


class CollectChangedPackagesTest(unittest.TestCase):
    WORKFLOW_PATH = ".github/workflows/ci.yml"

    def test_should_combine_lockfile_and_workflow_changes(self) -> None:
        repository = FakeRepository(
            {
                "base": {
                    "package-lock.json": build_lockfile(
                        {"node_modules/a": {"version": "1.0.0"}}
                    ),
                    self.WORKFLOW_PATH: "- uses: actions/checkout@v3.0.0\n",
                },
                "head": {
                    "package-lock.json": build_lockfile(
                        {"node_modules/a": {"version": "1.1.0"}}
                    ),
                    self.WORKFLOW_PATH: "- uses: actions/checkout@v4.0.0\n",
                },
            }
        )
        changed = check_cve.collect_changed_packages(repository, "base", "head")
        self.assertEqual(
            [(p.ecosystem, p.name, p.version) for p in changed],
            [("npm", "a", "1.1.0"), ("GitHub Actions", "actions/checkout", "4.0.0")],
        )

    def test_should_return_nothing_when_no_lockfile_and_no_workflow_exist(
        self,
    ) -> None:
        repository = FakeRepository({"base": {"README.md": "x"}, "head": {}})
        self.assertEqual(
            check_cve.collect_changed_packages(repository, "base", "head"), []
        )

    def test_should_treat_missing_base_lockfile_as_empty(self) -> None:
        repository = FakeRepository(
            {
                "base": {},
                "head": {
                    "package-lock.json": build_lockfile(
                        {"node_modules/a": {"version": "1.0.0"}}
                    )
                },
            }
        )
        changed = check_cve.collect_changed_packages(repository, "base", "head")
        self.assertEqual([p.name for p in changed], ["a"])

    def test_should_raise_for_unknown_ref(self) -> None:
        repository = FakeRepository({"base": {}})
        with self.assertRaises(CheckCveError):
            check_cve.collect_changed_packages(repository, "base", "missing")


class RunTest(unittest.TestCase):
    def run_cli(
        self,
        argv: Sequence[str],
        client: FakeOsvClient,
        repository: FakeRepository | None = None,
    ) -> tuple[ExitStatus, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = check_cve.run(
                argv, client, repository or FakeRepository()
            )
        return status, output.getvalue()

    def test_should_exit_vulnerable_for_vulnerable_spec(self) -> None:
        client = FakeOsvClient(
            {"lodash@4.17.20": ["GHSA-1"]},
            {"GHSA-1": build_vulnerability("GHSA-1", package_name="lodash")},
        )
        status, _ = self.run_cli(["lodash@4.17.20"], client)
        self.assertEqual(status, ExitStatus.VULNERABLE)

    def test_should_exit_clean_for_clean_spec(self) -> None:
        status, output = self.run_cli(["lodash@4.17.21"], FakeOsvClient())
        self.assertEqual(
            (status, output.splitlines()[-1]),
            (ExitStatus.CLEAN, "RESULT: no known vulnerabilities."),
        )

    def test_should_pass_ecosystem_option_to_query(self) -> None:
        client = FakeOsvClient()
        self.run_cli(["--ecosystem", "PyPI", "requests@2.0.0"], client)
        self.assertEqual(client.queried_ecosystems, ["PyPI"])

    def test_should_print_json_when_requested(self) -> None:
        _, output = self.run_cli(["--json", "lodash@4.17.21"], FakeOsvClient())
        self.assertEqual(json.loads(output)[0]["name"], "lodash")

    def test_should_check_changed_versions_in_git_mode(self) -> None:
        repository = FakeRepository(
            {
                "base": {},
                "head": {
                    "package-lock.json": build_lockfile(
                        {"node_modules/a": {"version": "1.0.0"}}
                    )
                },
            }
        )
        client = FakeOsvClient(
            {"a@1.0.0": ["GHSA-1"]},
            {"GHSA-1": build_vulnerability("GHSA-1", package_name="a")},
        )
        status, _ = self.run_cli(["--git", "base", "head"], client, repository)
        self.assertEqual(status, ExitStatus.VULNERABLE)

    def test_should_exit_clean_in_git_mode_without_changes(self) -> None:
        repository = FakeRepository({"base": {}, "head": {}})
        status, output = self.run_cli(
            ["--git", "base", "head"], FakeOsvClient(), repository
        )
        self.assertEqual(
            (status, output.strip()),
            (ExitStatus.CLEAN, "No changed dependency versions to check."),
        )

    def test_should_exit_with_usage_error_without_arguments(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                self.run_cli([], FakeOsvClient())
        self.assertEqual(raised.exception.code, 2)

    def test_should_exit_with_usage_error_for_specs_combined_with_git(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                self.run_cli(["--git", "a", "b", "x@1"], FakeOsvClient())
        self.assertEqual(raised.exception.code, 2)

    def test_should_raise_for_invalid_spec(self) -> None:
        with self.assertRaises(CheckCveError):
            self.run_cli(["lodash"], FakeOsvClient())


class MainTest(unittest.TestCase):
    def test_should_return_error_status_and_message_on_failure(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            status = check_cve.main(["lodash"])
        self.assertEqual(
            (status, stderr.getvalue().startswith("error: ")),
            (ExitStatus.ERROR, True),
        )


class GitRepositoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.run_git("init", "-q")
        self.write("package-lock.json", "{}")
        self.write(".github/workflows/ci.yml", "x")
        self.write(".github/workflows/notes.txt", "x")
        self.write("other/ci.yml", "x")
        self.run_git("add", "-A")
        self.run_git("commit", "-q", "-m", "init")
        self.repository = check_cve.GitRepository(self.root)

    def run_git(self, *args: str) -> None:
        environment = {
            **os.environ,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        subprocess.run(
            ["git", *args],
            cwd=self.root,
            env=environment,
            check=True,
            capture_output=True,
        )

    def write(self, relative_path: str, text: str) -> None:
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_should_read_file_at_ref(self) -> None:
        self.assertEqual(self.repository.read_file("HEAD", "package-lock.json"), "{}")

    def test_should_return_empty_text_for_missing_file(self) -> None:
        self.assertEqual(self.repository.read_file("HEAD", "absent.json"), "")

    def test_should_list_only_yaml_files_under_workflows(self) -> None:
        self.assertEqual(
            self.repository.list_workflow_files("HEAD"),
            [".github/workflows/ci.yml"],
        )

    def test_should_reject_ref_that_looks_like_an_option(self) -> None:
        with self.assertRaises(CheckCveError):
            self.repository.verify_ref("--all")

    def test_should_accept_existing_ref(self) -> None:
        self.repository.verify_ref("HEAD")

    def test_should_reject_unknown_ref(self) -> None:
        with self.assertRaises(CheckCveError):
            self.repository.verify_ref("no-such-ref")


if __name__ == "__main__":
    unittest.main()
