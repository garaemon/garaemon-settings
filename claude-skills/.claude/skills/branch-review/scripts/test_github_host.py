"""Tests for deriving the GitHub host from the origin remote.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import unittest

from commands import build_gh_environment, parse_host_from_remote_url


class ParseHostFromRemoteUrlTest(unittest.TestCase):
    """parse_host_from_remote_url pulls the hostname out of a git remote URL."""

    def test_reads_an_https_url(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("https://github.com/owner/repo.git"),
            "github.com",
        )

    def test_reads_an_scp_style_ssh_url(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("git@github.com:owner/repo.git"),
            "github.com",
        )

    def test_reads_an_enterprise_host(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("git@github.example.com:owner/repo.git"),
            "github.example.com",
        )

    def test_reads_an_ssh_url_with_a_port(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("ssh://git@github.example.com:2222/owner/repo.git"),
            "github.example.com",
        )

    def test_drops_userinfo_from_an_https_url(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("https://user:token@github.example.com/owner/repo"),
            "github.example.com",
        )

    def test_lowercases_the_host(self) -> None:
        self.assertEqual(
            parse_host_from_remote_url("https://GitHub.Example.COM/owner/repo"),
            "github.example.com",
        )

    def test_returns_none_for_a_local_path(self) -> None:
        self.assertIsNone(parse_host_from_remote_url("/srv/git/repo.git"))

    def test_returns_none_for_a_local_path_containing_a_colon(self) -> None:
        # The colon comes after a slash, so this is a path and not the host
        # "/srv/git". Reading it as a host would export a nonsense GH_HOST and
        # fail every gh call.
        self.assertIsNone(parse_host_from_remote_url("/srv/git:mirror/repo.git"))

    def test_returns_none_for_a_relative_path_containing_a_colon(self) -> None:
        self.assertIsNone(parse_host_from_remote_url("./work:repo/.git"))

    def test_returns_none_for_a_windows_drive_letter(self) -> None:
        self.assertIsNone(parse_host_from_remote_url("C:/src/repo"))

    def test_returns_none_for_an_empty_url(self) -> None:
        self.assertIsNone(parse_host_from_remote_url(""))


class BuildGhEnvironmentTest(unittest.TestCase):
    """build_gh_environment sets GH_HOST from the detected host."""

    def test_sets_gh_host_when_a_host_is_detected(self) -> None:
        environment = build_gh_environment("github.example.com", base_environment={})
        self.assertEqual(environment["GH_HOST"], "github.example.com")

    def test_overrides_an_inherited_gh_host(self) -> None:
        # The repository is authoritative: an exported GH_HOST pointing at a
        # different host would send every call to the wrong server.
        environment = build_gh_environment(
            "github.example.com", base_environment={"GH_HOST": "github.com"}
        )
        self.assertEqual(environment["GH_HOST"], "github.example.com")

    def test_leaves_gh_host_alone_when_no_host_is_detected(self) -> None:
        environment = build_gh_environment(None, base_environment={"GH_HOST": "keep.me"})
        self.assertEqual(environment["GH_HOST"], "keep.me")

    def test_preserves_other_variables(self) -> None:
        environment = build_gh_environment(
            "github.example.com", base_environment={"PATH": "/usr/bin"}
        )
        self.assertEqual(environment["PATH"], "/usr/bin")


if __name__ == "__main__":
    unittest.main()
