"""Tests for post_gist.py.

A fake `gh` on PATH records its arguments and GH_HOST and publishes the files
to a local bare repository, so no network or credentials are needed.

Run with: python3 -m unittest discover -s scripts
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

import post_gist

SCRIPT_PATH = Path(__file__).resolve().parent / "post_gist.py"
GIST_URL = "https://gist.github.com/tester/abc123"
SSH_GIST_URL = "git@gist.github.com:tester/abc123.git"
PNG_BYTES = b"\x89PNG\r\n\x1a\n"


class ParseHostFromRemoteUrlTest(unittest.TestCase):
    def test_should_read_https_url(self) -> None:
        self.assertEqual(
            post_gist.parse_host_from_remote_url("https://ghe.example.com/o/r.git"),
            "ghe.example.com",
        )

    def test_should_read_scp_like_url(self) -> None:
        self.assertEqual(
            post_gist.parse_host_from_remote_url("git@ghe.example.com:o/r.git"),
            "ghe.example.com",
        )

    def test_should_read_ssh_url_with_port(self) -> None:
        self.assertEqual(
            post_gist.parse_host_from_remote_url("ssh://git@ghe.example.com:2222/o/r.git"),
            "ghe.example.com",
        )

    def test_should_return_none_for_local_path(self) -> None:
        self.assertIsNone(post_gist.parse_host_from_remote_url("/srv/git/repo.git"))


class ConvertToSshUrlTest(unittest.TestCase):
    def test_should_convert_github_gist_url(self) -> None:
        self.assertEqual(
            post_gist.convert_to_ssh_url(f"{GIST_URL}.git"), SSH_GIST_URL
        )

    def test_should_keep_path_of_enterprise_gist_url(self) -> None:
        self.assertEqual(
            post_gist.convert_to_ssh_url("https://ghe.example.com/gist/abc123.git"),
            "git@ghe.example.com:gist/abc123.git",
        )


class RewriteImageLinksTest(unittest.TestCase):
    RAW_URL = f"{GIST_URL}/raw/chart.png"

    def rewrite(self, text: str) -> str:
        return post_gist.rewrite_image_links(text, "chart.png", self.RAW_URL)

    def test_should_rewrite_markdown_link(self) -> None:
        self.assertEqual(
            self.rewrite("![c](images/chart.png)"), f"![c]({self.RAW_URL})"
        )

    def test_should_rewrite_link_with_title(self) -> None:
        self.assertEqual(
            self.rewrite('![c](chart.png "p99")'), f'![c]({self.RAW_URL} "p99")'
        )

    def test_should_rewrite_html_img_src(self) -> None:
        self.assertEqual(
            self.rewrite('<img src="./chart.png" width="3">'),
            f'<img src="{self.RAW_URL}" width="3">',
        )

    def test_should_rewrite_reference_definition(self) -> None:
        self.assertEqual(
            self.rewrite("![c][id]\n\n[id]: images/chart.png\n"),
            f"![c][id]\n\n[id]: {self.RAW_URL}\n",
        )

    def test_should_leave_other_links_untouched(self) -> None:
        text = "![x](other.png) [t](chart.png.txt) [u](not-chart.png)"
        self.assertEqual(self.rewrite(text), text)


class FindReferencedImagePathsTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.work = Path(temporary_directory.name)
        (self.work / "images").mkdir()
        self.image = self.work / "images" / "chart.png"
        self.image.write_bytes(PNG_BYTES)

    def find_references(self, text: str) -> post_gist.ReferencedImages:
        report = self.work / "report.md"
        report.write_text(text)
        return post_gist.find_referenced_image_paths(report)

    def find(self, text: str) -> list[Path]:
        return self.find_references(text).existing

    def test_should_find_inline_link(self) -> None:
        self.assertEqual(self.find("![c](images/chart.png)"), [self.image])

    def test_should_find_link_with_title(self) -> None:
        self.assertEqual(self.find('![c](images/chart.png "p99")'), [self.image])

    def test_should_find_html_img_src(self) -> None:
        self.assertEqual(self.find('<img src="./images/chart.png">'), [self.image])

    def test_should_find_reference_definition(self) -> None:
        self.assertEqual(self.find("![c][id]\n\n[id]: images/chart.png\n"), [self.image])

    def test_should_ignore_remote_urls(self) -> None:
        self.assertEqual(self.find("![c](https://example.com/chart.png)"), [])

    def test_should_not_list_missing_file_as_existing(self) -> None:
        self.assertEqual(self.find("![c](images/missing.png)"), [])

    def test_should_report_missing_file(self) -> None:
        references = self.find_references("![c](images/missing.png)")
        self.assertEqual(references.missing, [self.work / "images" / "missing.png"])

    def test_should_not_report_remote_url_as_missing(self) -> None:
        references = self.find_references("![c](https://example.com/chart.png)")
        self.assertEqual(references.missing, [])

    def test_should_not_report_non_image_link_as_missing(self) -> None:
        references = self.find_references("[t](notes/missing.md)")
        self.assertEqual(references.missing, [])

    def test_should_ignore_non_image_links(self) -> None:
        self.assertEqual(self.find("[t](images/chart.png.txt)"), [])

    def test_should_list_repeated_reference_once(self) -> None:
        self.assertEqual(
            self.find("![a](images/chart.png) ![b](images/chart.png)"), [self.image]
        )


class PostGistCommandTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(temporary_directory.cleanup)
        self.work = Path(temporary_directory.name)
        self.remote_gist = self.work / "remote" / "abc123.git"
        self.record_file = self.work / "record.json"
        self.temporary_root = self.work / "tmp-root"
        self.temporary_root.mkdir()
        self.install_fake_gh()
        self.report = self.write_file("report.md", "# Report\n")
        self.image = self.work / "images" / "chart.png"
        self.image.parent.mkdir()
        self.image.write_bytes(PNG_BYTES)

    def install_fake_gh(self) -> None:
        fake_bin = self.work / "bin"
        fake_bin.mkdir()
        fake_gh = fake_bin / "gh"
        fake_gh.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import json, os, shutil, subprocess, sys
                from pathlib import Path

                arguments = sys.argv[1:]
                if arguments[0] == "api":
                    api_remote = Path({str(self.remote_gist)!r})
                    def read_remote(*command):
                        return subprocess.run(
                            ["git", "-C", str(api_remote), *command], check=True,
                            capture_output=True, text=True).stdout.strip()
                    sha = read_remote("rev-parse", "main")
                    names = read_remote("ls-tree", "--name-only", "main").splitlines()
                    print(json.dumps({{
                        "git_pull_url": {GIST_URL!r} + ".git",
                        "files": {{name: {{"raw_url":
                            f"{GIST_URL}/raw/{{sha}}/{{name}}"}} for name in names}},
                    }}))
                    sys.exit(0)
                Path({str(self.record_file)!r}).write_text(
                    json.dumps({{"gh_host": os.environ.get("GH_HOST", ""),
                                "args": arguments}})
                )
                seed = Path({str(self.work / "seed")!r})
                remote = Path({str(self.remote_gist)!r})
                shutil.rmtree(seed, ignore_errors=True)
                shutil.rmtree(remote, ignore_errors=True)
                seed.mkdir()
                remaining = iter(arguments[2:])
                for argument in remaining:
                    if argument == "-d":
                        next(remaining)
                    elif not argument.startswith("-"):
                        shutil.copy(argument, seed)
                def git(*command, cwd=seed):
                    subprocess.run(["git", *command], cwd=cwd, check=True,
                                   stderr=subprocess.DEVNULL)
                git("init", "-q", "--bare", str(remote), cwd=seed)
                git("init", "-q")
                git("add", "-A")
                git("-c", "user.name=t", "-c", "user.email=t@example.com",
                    "commit", "-q", "-m", "seed")
                git("push", "-q", str(remote), "HEAD:refs/heads/main")
                git("symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
                if os.environ.get("FAKE_GH_REJECT_PUSH"):
                    hook = remote / "hooks" / "pre-receive"
                    hook.write_text("#!/bin/sh\\nexit 1\\n")
                    hook.chmod(0o755)
                print(os.environ.get("FAKE_GH_CREATE_URL") or {GIST_URL!r})
                """
            )
        )
        fake_gh.chmod(0o755)

    def write_file(self, relative_path: str, content: str) -> Path:
        path = self.work / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def make_repository(self, origin_url: str | None) -> Path:
        repository = Path(tempfile.mkdtemp(prefix="repo-", dir=self.work))
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        if origin_url is not None:
            subprocess.run(
                ["git", "-C", str(repository), "remote", "add", "origin", origin_url],
                check=True,
            )
        return repository

    def run_script(
        self,
        origin_url: str | None,
        *arguments: object,
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess:
        repository = self.make_repository(origin_url)
        environment = {
            "PATH": f"{self.work / 'bin'}:/usr/bin:/bin:/usr/local/bin",
            "HOME": str(self.work),
            "TMPDIR": str(self.temporary_root),
            "GIT_CONFIG_COUNT": "1",
            "GIT_CONFIG_KEY_0": f"url.{self.remote_gist}.insteadOf",
            "GIT_CONFIG_VALUE_0": f"{GIST_URL}.git",
            # Fail SSH at once so a test never reaches the network.
            "GIT_SSH_COMMAND": "false",
            **(extra_env or {}),
        }
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), *map(str, arguments)],
            cwd=repository,
            env=environment,
            capture_output=True,
            text=True,
        )

    def run_on_github(self, *arguments: object, **keyword_arguments) -> (
        subprocess.CompletedProcess
    ):
        return self.run_script(
            "https://github.com/owner/repo", *arguments, **keyword_arguments
        )

    def read_record(self) -> dict:
        return json.loads(self.record_file.read_text())

    def assert_links_to_raw_image(self, text: str, image_name: str) -> None:
        self.assertRegex(
            text, rf"{re.escape(GIST_URL)}/raw/[0-9a-f]{{40}}/{re.escape(image_name)}"
        )

    def read_remote_file(self, name: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.remote_gist), "show", f"main:{name}"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def remote_has_file(self, name: str) -> bool:
        return (
            subprocess.run(
                ["git", "-C", str(self.remote_gist), "cat-file", "-e", f"main:{name}"],
                stderr=subprocess.DEVNULL,
            ).returncode
            == 0
        )

    def assert_rejected(
        self, result: subprocess.CompletedProcess, expected_message: str
    ) -> None:
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(expected_message, result.stderr)
        self.assertFalse(self.record_file.exists(), "gh must not run")


class HostDetectionTest(PostGistCommandTest):
    def test_should_use_host_from_https_remote(self) -> None:
        self.run_script("https://ghe.example.com/owner/repo.git", self.report)
        self.assertEqual(self.read_record()["gh_host"], "ghe.example.com")

    def test_should_use_host_from_scp_like_remote(self) -> None:
        self.run_script("git@ghe.example.com:owner/repo.git", self.report)
        self.assertEqual(self.read_record()["gh_host"], "ghe.example.com")

    def test_should_use_host_from_ssh_url_with_port(self) -> None:
        self.run_script("ssh://git@ghe.example.com:2222/owner/repo.git", self.report)
        self.assertEqual(self.read_record()["gh_host"], "ghe.example.com")

    def test_should_override_inherited_gh_host(self) -> None:
        self.run_on_github(self.report, extra_env={"GH_HOST": "stale.example.com"})
        self.assertEqual(self.read_record()["gh_host"], "github.com")

    def test_should_fail_without_origin_remote(self) -> None:
        result = self.run_script(None, self.report)
        self.assert_rejected(result, "no 'origin' remote")

    def test_should_fail_when_origin_url_has_no_host(self) -> None:
        result = self.run_script("/srv/git/repo.git", self.report)
        self.assert_rejected(result, "cannot find a host")


class GistCreationTest(PostGistCommandTest):
    def test_should_create_secret_gist_by_default(self) -> None:
        self.run_on_github(self.report)
        self.assertNotIn("--public", self.read_record()["args"])

    def test_should_create_public_gist_when_requested(self) -> None:
        self.run_on_github("--public", self.report)
        self.assertIn("--public", self.read_record()["args"])

    def test_should_pass_description(self) -> None:
        self.run_on_github("--description", "Weekly report", self.report)
        arguments = self.read_record()["args"]
        self.assertEqual(arguments[arguments.index("-d") + 1], "Weekly report")

    def test_should_print_gist_url(self) -> None:
        result = self.run_on_github(self.report)
        self.assertEqual(result.stdout.strip(), GIST_URL)

    def test_should_upload_multiple_markdown_files(self) -> None:
        japanese = self.write_file("report.ja.md", "# Report ja\n")
        self.run_on_github(self.report, japanese)
        arguments = self.read_record()["args"]
        self.assertIn(str(self.report), arguments)
        self.assertIn(str(japanese), arguments)

    def test_should_accept_uppercase_markdown_extension(self) -> None:
        upper = self.write_file("UPPER.MD", "# Upper\n")
        self.assertEqual(self.run_on_github(upper).returncode, 0)

    def test_should_accept_markdown_name_with_single_quote(self) -> None:
        quoted = self.write_file("it's.md", "# quoted\n")
        self.assertEqual(self.run_on_github(quoted).returncode, 0)

    def test_should_accept_paths_with_spaces_as_distinct(self) -> None:
        first = self.write_file("a b/one.md", "# one\n")
        second = self.write_file("x b/two.md", "# two\n")
        self.assertEqual(self.run_on_github(first, second).returncode, 0)


class InputValidationTest(PostGistCommandTest):
    def test_should_fail_when_file_is_missing(self) -> None:
        result = self.run_on_github(self.work / "missing.md")
        self.assert_rejected(result, "file not found")

    def test_should_fail_when_file_has_unsupported_extension(self) -> None:
        text_file = self.write_file("report.txt", "text")
        result = self.run_on_github(text_file)
        self.assert_rejected(result, "only .md files and images")

    def test_should_fail_without_arguments(self) -> None:
        result = self.run_on_github()
        self.assert_rejected(result, "usage:")

    def test_should_fail_when_no_markdown_file_is_given(self) -> None:
        result = self.run_on_github(self.image)
        self.assert_rejected(result, "no Markdown file")

    def test_should_fail_when_image_file_is_missing(self) -> None:
        result = self.run_on_github(self.report, self.work / "images" / "missing.png")
        self.assert_rejected(result, "file not found")

    def test_should_fail_when_image_basenames_collide(self) -> None:
        other = self.work / "other" / "chart.png"
        other.parent.mkdir()
        other.write_bytes(PNG_BYTES)
        result = self.run_on_github(self.report, self.image, other)
        self.assert_rejected(result, "share the name 'chart.png'")

    def test_should_fail_when_markdown_basenames_collide(self) -> None:
        other = self.write_file("other/report.md", "# other\n")
        result = self.run_on_github(self.report, other)
        self.assert_rejected(result, "share the name 'report.md'")

    def test_should_fail_when_image_name_has_unsafe_characters(self) -> None:
        unsafe = self.work / "images" / "bad name&.png"
        unsafe.write_bytes(PNG_BYTES)
        result = self.run_on_github(self.report, unsafe)
        self.assert_rejected(result, "unsafe image file name")


class ImageEmbeddingTest(PostGistCommandTest):
    def test_should_push_image_to_gist_repository(self) -> None:
        self.run_on_github(self.report, self.image)
        self.assertTrue(self.remote_has_file("chart.png"))

    def test_should_not_pass_image_to_gist_create(self) -> None:
        self.run_on_github(self.report, self.image)
        self.assertNotIn(str(self.image), self.read_record()["args"])

    def test_should_accept_uppercase_image_extension(self) -> None:
        upper = self.work / "images" / "Shot.PNG"
        upper.write_bytes(PNG_BYTES)
        self.assertEqual(self.run_on_github(self.report, upper).returncode, 0)
        self.assertTrue(self.remote_has_file("Shot.PNG"))

    def test_should_rewrite_links_in_every_markdown_file(self) -> None:
        english = self.write_file("doc.en.md", "![c](images/chart.png)\n")
        japanese = self.write_file("doc.ja.md", '<img src="./images/chart.png">\n')
        self.run_on_github(english, japanese, self.image)
        self.assert_links_to_raw_image(self.read_remote_file("doc.en.md"), "chart.png")
        self.assert_links_to_raw_image(self.read_remote_file("doc.ja.md"), "chart.png")


class AutomaticImageDiscoveryTest(PostGistCommandTest):
    def write_report_referencing_image(self, name: str = "doc.md") -> Path:
        return self.write_file(name, "![c](images/chart.png)\n")

    def test_should_upload_image_referenced_by_markdown(self) -> None:
        report = self.write_report_referencing_image()
        self.run_on_github(report)
        self.assertTrue(self.remote_has_file("chart.png"))

    def test_should_rewrite_link_of_discovered_image(self) -> None:
        report = self.write_report_referencing_image()
        self.run_on_github(report)
        self.assert_links_to_raw_image(self.read_remote_file("doc.md"), "chart.png")

    def test_should_not_pass_discovered_image_to_gist_create(self) -> None:
        report = self.write_report_referencing_image()
        self.run_on_github(report)
        self.assertNotIn(str(self.image), self.read_record()["args"])

    def test_should_accept_explicit_image_that_is_also_referenced(self) -> None:
        report = self.write_report_referencing_image()
        result = self.run_on_github(report, self.image)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_should_share_image_referenced_by_both_languages(self) -> None:
        english = self.write_report_referencing_image("doc.en.md")
        japanese = self.write_report_referencing_image("doc.ja.md")
        result = self.run_on_github(english, japanese)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_should_fail_when_referenced_image_is_missing(self) -> None:
        report = self.write_file("doc.md", "![c](images/missing.png)\n")
        result = self.run_on_github(report)
        self.assert_rejected(result, "referenced image not found")

    def test_should_name_markdown_file_and_target_when_image_is_missing(self) -> None:
        report = self.write_file("doc.md", "![c](images/missing.png)\n")
        result = self.run_on_github(report)
        self.assertIn("doc.md", result.stderr)
        self.assertIn("images/missing.png", result.stderr)

    def test_should_create_gist_when_missing_image_is_ignored(self) -> None:
        report = self.write_file("doc.md", "![c](images/missing.png)\n")
        result = self.run_on_github("--ignore-missing-images", report)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_should_leave_link_of_ignored_missing_image(self) -> None:
        report = self.write_file(
            "doc.md", "![c](images/missing.png)\n![d](images/chart.png)\n"
        )
        self.run_on_github("--ignore-missing-images", report)
        remote_text = self.read_remote_file("doc.md")
        self.assertIn("(images/missing.png)", remote_text)
        self.assert_links_to_raw_image(remote_text, "chart.png")

    def test_should_skip_image_upload_when_nothing_is_referenced(self) -> None:
        result = self.run_on_github(self.report)
        self.assertNotIn("uploading images", result.stderr)


class RawUrlFromApiTest(PostGistCommandTest):
    def test_should_use_raw_url_that_the_api_reports(self) -> None:
        report = self.write_file("doc.md", "![c](images/chart.png)\n")
        self.run_on_github(report)
        self.assertRegex(
            self.read_remote_file("doc.md"),
            rf"\({GIST_URL}/raw/[0-9a-f]{{40}}/chart\.png\)",
        )

    def test_should_keep_user_name_when_gh_prints_url_without_it(self) -> None:
        report = self.write_file("doc.md", "![c](images/chart.png)\n")
        self.run_on_github(
            report,
            extra_env={"FAKE_GH_CREATE_URL": "https://gist.github.com/abc123"},
        )
        self.assertIn("/tester/abc123/raw/", self.read_remote_file("doc.md"))

    def test_should_push_images_before_markdown_links_change(self) -> None:
        report = self.write_file("doc.md", "![c](images/chart.png)\n")
        self.run_on_github(report)
        commit_count = subprocess.run(
            ["git", "-C", str(self.remote_gist), "rev-list", "--count", "main"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        self.assertEqual(commit_count, "3")


class SshPreferenceTest(PostGistCommandTest):
    def run_with_gist_urls(
        self, ssh_target: Path, https_target: Path
    ) -> subprocess.CompletedProcess:
        return self.run_on_github(
            self.report,
            self.image,
            extra_env={
                "GIT_CONFIG_COUNT": "2",
                "GIT_CONFIG_KEY_0": f"url.{https_target}.insteadOf",
                "GIT_CONFIG_VALUE_0": f"{GIST_URL}.git",
                "GIT_CONFIG_KEY_1": f"url.{ssh_target}.insteadOf",
                "GIT_CONFIG_VALUE_1": SSH_GIST_URL,
            },
        )

    def test_should_push_over_ssh_when_ssh_works(self) -> None:
        self.run_with_gist_urls(self.remote_gist, self.work / "unreachable")
        self.assertTrue(self.remote_has_file("chart.png"))

    def test_should_fall_back_to_https_when_ssh_fails(self) -> None:
        self.run_with_gist_urls(self.work / "unreachable", self.remote_gist)
        self.assertTrue(self.remote_has_file("chart.png"))

    def test_should_report_ssh_failure_before_falling_back(self) -> None:
        result = self.run_with_gist_urls(self.work / "unreachable", self.remote_gist)
        self.assertIn("SSH clone failed", result.stderr)

    def test_should_not_report_ssh_failure_when_ssh_works(self) -> None:
        result = self.run_with_gist_urls(self.remote_gist, self.work / "unreachable")
        self.assertNotIn("SSH clone failed", result.stderr)


class ImagePushFailureTest(PostGistCommandTest):
    def run_with_rejected_push(self, origin_url: str) -> subprocess.CompletedProcess:
        return self.run_script(
            origin_url,
            self.report,
            self.image,
            extra_env={"FAKE_GH_REJECT_PUSH": "1"},
        )

    def test_should_fail_when_image_push_is_rejected(self) -> None:
        result = self.run_with_rejected_push("https://github.com/owner/repo")
        self.assertNotEqual(result.returncode, 0)

    def test_should_report_gist_url_when_image_push_fails(self) -> None:
        result = self.run_with_rejected_push("https://github.com/owner/repo")
        self.assertIn(GIST_URL, result.stderr)

    def test_should_name_gist_host_in_recovery_command(self) -> None:
        result = self.run_with_rejected_push("https://ghe.example.com/owner/repo")
        self.assertIn("GH_HOST=ghe.example.com gh gist delete abc123", result.stderr)

    def test_should_remove_temporary_directory_when_image_push_fails(self) -> None:
        self.run_with_rejected_push("https://github.com/owner/repo")
        self.assertEqual(list(self.temporary_root.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
