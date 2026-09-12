"""Tests for rendering review.json into REVIEW.md and REVIEW.html.

Run with: uv run --project <skill_dir> -m unittest discover -s scripts -t scripts
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import tempfile
import unittest
from typing import Any

import render_review
from render_review import (
    HTML_REPORT_NAME,
    MARKDOWN_REPORT_NAME,
    NO_FINDINGS_TEXT,
    check_review,
    load_review,
    read_template,
    render_html_report,
    render_inline_markdown,
    render_markdown_report,
    render_markdown_subset,
    validate_review,
    write_reports,
)

GENERATED_AT = "2026-09-12 10:00 UTC"


def build_finding(**overrides: Any) -> dict[str, Any]:
    """Return one finding with every field set, overridden by the keywords."""
    finding: dict[str, Any] = {
        "id": "2-1",
        "title": "IPC color inputs not validated",
        "path": "src/main/index.ts",
        "line": 29,
        "body": "The handler accepts any string.",
    }
    finding.update(overrides)
    return finding


def build_review(**overrides: Any) -> dict[str, Any]:
    """Return a review with one Security finding, overridden by the keywords."""
    review: dict[str, Any] = {
        "title": "Code Review: add color picker",
        "branch": "feature/color-picker",
        "range": "whole branch against main",
        "pull_request": "https://github.com/octo/repo/pull/12",
        "stats": {"files": 3, "additions": 120, "deletions": 8},
        "overall_comments": "Documentation is **missing** throughout.",
        "categories": [
            {"number": 1, "name": "Architecture / Config", "findings": []},
            {"number": 2, "name": "Security", "findings": [build_finding()]},
        ],
    }
    review.update(overrides)
    return review


class ValidateReviewTest(unittest.TestCase):
    """validate_review names the first missing or ill-typed key."""

    def test_accepts_a_review_with_every_field(self) -> None:
        validate_review(build_review())

    def test_accepts_a_finding_without_a_path(self) -> None:
        finding = build_finding()
        del finding["path"]
        del finding["line"]
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [finding]},
        ])
        validate_review(review)

    def test_rejects_a_missing_title(self) -> None:
        review = build_review()
        del review["title"]
        with self.assertRaisesRegex(ValueError, "title"):
            validate_review(review)

    def test_rejects_missing_categories(self) -> None:
        review = build_review()
        del review["categories"]
        with self.assertRaisesRegex(ValueError, "categories"):
            validate_review(review)

    def test_rejects_a_finding_without_an_id(self) -> None:
        finding = build_finding()
        del finding["id"]
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [finding]},
        ])
        with self.assertRaisesRegex(ValueError, "id"):
            validate_review(review)

    def test_rejects_a_finding_without_a_body(self) -> None:
        finding = build_finding()
        del finding["body"]
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [finding]},
        ])
        with self.assertRaisesRegex(ValueError, "body"):
            validate_review(review)

    def test_rejects_a_non_integer_line(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [build_finding(line="29")]},
        ])
        with self.assertRaisesRegex(ValueError, "line"):
            validate_review(review)

    def test_rejects_duplicate_finding_ids(self) -> None:
        # Duplicate ids would give two cards the same anchor, so the summary
        # table would silently link both rows to the first card.
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(), build_finding(title="Other")]},
        ])
        with self.assertRaisesRegex(ValueError, "2-1"):
            validate_review(review)


class LoadReviewTest(unittest.TestCase):
    """load_review reads and validates the JSON file."""

    def test_reads_a_review_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            review_path = pathlib.Path(directory) / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            self.assertEqual(load_review(review_path)["title"], build_review()["title"])

    def test_propagates_a_json_decode_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            review_path = pathlib.Path(directory) / "review.json"
            review_path.write_text('{"title": ', encoding="utf-8")
            with self.assertRaises(json.JSONDecodeError):
                load_review(review_path)


class RenderInlineMarkdownTest(unittest.TestCase):
    """render_inline_markdown handles code spans and bold, escaping everything."""

    def test_escapes_html_characters(self) -> None:
        self.assertEqual(render_inline_markdown('a < b & "c"'), "a &lt; b &amp; &quot;c&quot;")

    def test_wraps_backticks_in_code(self) -> None:
        self.assertEqual(render_inline_markdown("use `foo()`"), "use <code>foo()</code>")

    def test_wraps_double_asterisks_in_strong(self) -> None:
        self.assertEqual(render_inline_markdown("is **wrong**"), "is <strong>wrong</strong>")

    def test_leaves_asterisks_inside_code_alone(self) -> None:
        self.assertEqual(render_inline_markdown("`**kwargs`"), "<code>**kwargs</code>")

    def test_escapes_html_inside_code(self) -> None:
        self.assertEqual(
            render_inline_markdown("`<script>`"), "<code>&lt;script&gt;</code>"
        )


class RenderMarkdownSubsetTest(unittest.TestCase):
    """render_markdown_subset turns the supported block types into HTML."""

    def test_wraps_text_in_a_paragraph(self) -> None:
        self.assertEqual(render_markdown_subset("hello"), "<p>hello</p>")

    def test_splits_paragraphs_on_blank_lines(self) -> None:
        self.assertEqual(render_markdown_subset("one\n\ntwo"), "<p>one</p>\n<p>two</p>")

    def test_renders_a_fenced_block_with_its_language(self) -> None:
        rendered = render_markdown_subset("```ts\nconst a = 1 < 2;\n```")
        self.assertEqual(
            rendered, '<pre><code class="language-ts">const a = 1 &lt; 2;</code></pre>'
        )

    def test_keeps_a_dash_line_inside_a_fence_as_code(self) -> None:
        rendered = render_markdown_subset("```\n- not a list\n```")
        self.assertIn("<code>- not a list</code>", rendered)
        self.assertNotIn("<ul>", rendered)

    def test_closes_an_unterminated_fence_at_the_end(self) -> None:
        rendered = render_markdown_subset("```\nline one\nline two")
        self.assertEqual(rendered, "<pre><code>line one\nline two</code></pre>")

    def test_does_not_apply_bold_inside_a_fence(self) -> None:
        rendered = render_markdown_subset("```\n**raw**\n```")
        self.assertIn("**raw**", rendered)
        self.assertNotIn("<strong>", rendered)

    def test_renders_dash_lines_as_one_unordered_list(self) -> None:
        rendered = render_markdown_subset("- one\n- `two`")
        self.assertEqual(rendered, "<ul>\n<li>one</li>\n<li><code>two</code></li>\n</ul>")

    def test_renders_numbered_lines_as_an_ordered_list(self) -> None:
        rendered = render_markdown_subset("1. first\n2. second")
        self.assertEqual(rendered, "<ol>\n<li>first</li>\n<li>second</li>\n</ol>")

    def test_renders_quoted_lines_as_a_blockquote(self) -> None:
        rendered = render_markdown_subset("> consider splitting\n> the PR")
        self.assertEqual(
            rendered, "<blockquote><p>consider splitting\nthe PR</p></blockquote>"
        )

    def test_returns_an_empty_string_for_empty_text(self) -> None:
        self.assertEqual(render_markdown_subset("  \n"), "")


class RenderMarkdownReportTest(unittest.TestCase):
    """render_markdown_report reproduces the REVIEW.md structure from SKILL.md."""

    def test_starts_with_the_title_heading(self) -> None:
        report = render_markdown_report(build_review())
        self.assertTrue(report.startswith("# Code Review: add color picker\n"))

    def test_writes_the_branch_and_stats_lines(self) -> None:
        report = render_markdown_report(build_review())
        self.assertIn("Branch: `feature/color-picker`\n", report)
        self.assertIn("3 files changed, 120 insertions, 8 deletions\n", report)

    def test_numbers_the_category_headings(self) -> None:
        self.assertIn("\n## 2. Security\n", render_markdown_report(build_review()))

    def test_formats_the_finding_heading_with_its_location(self) -> None:
        report = render_markdown_report(build_review())
        self.assertIn(
            "### 2-1. [src/main/index.ts:29] IPC color inputs not validated\n", report
        )

    def test_omits_the_brackets_when_a_finding_has_no_path(self) -> None:
        finding = build_finding()
        del finding["path"]
        del finding["line"]
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [finding]},
        ])
        self.assertIn("### 2-1. IPC color inputs not validated\n",
                      render_markdown_report(review))

    def test_omits_empty_categories(self) -> None:
        self.assertNotIn("Architecture", render_markdown_report(build_review()))

    def test_keeps_the_body_markdown_verbatim(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(body="```ts\nlet x;\n```")]},
        ])
        self.assertIn("```ts\nlet x;\n```", render_markdown_report(review))

    def test_says_no_findings_when_every_category_is_empty(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": []},
        ])
        self.assertIn(NO_FINDINGS_TEXT, render_markdown_report(review))


class RenderHtmlReportTest(unittest.TestCase):
    """render_html_report fills the bundled template."""

    def setUp(self) -> None:
        self.template_text = read_template()

    def render(self, review: dict[str, Any]) -> str:
        return render_html_report(review, self.template_text, GENERATED_AT)

    def test_lists_every_finding_in_the_summary_table(self) -> None:
        page = self.render(build_review())
        self.assertIn('href="#finding-2-1"', page)
        self.assertIn("IPC color inputs not validated", page)

    def test_gives_each_card_the_anchor_the_summary_links_to(self) -> None:
        self.assertIn('id="finding-2-1"', self.render(build_review()))

    def test_counts_findings_on_the_category_chips(self) -> None:
        page = self.render(build_review())
        self.assertIn('data-category="2"', page)
        self.assertIn("Security <b>1</b>", page)

    def test_marks_the_page_as_having_findings(self) -> None:
        self.assertIn('class="has-findings"', self.render(build_review()))

    def test_marks_an_empty_review_as_having_no_findings(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": []},
        ])
        self.assertIn('class="no-findings"', self.render(review))

    def test_leaves_no_placeholder_or_dollar_behind(self) -> None:
        # The template may not contain a literal dollar sign, because
        # string.Template treats every one as a placeholder.
        self.assertNotIn("$", self.render(build_review()))

    def test_escapes_html_in_the_title_path_and_category_name(self) -> None:
        review = build_review(
            title="<script>alert(1)</script>",
            categories=[{
                "number": 2, "name": "<b>Security</b>",
                "findings": [build_finding(path="<img src=x>")],
            }],
        )
        page = self.render(review)
        self.assertNotIn("<script>alert", page)
        self.assertNotIn("<b>Security</b>", page)
        self.assertNotIn("<img src=x>", page)

    def test_omits_the_pull_request_row_when_absent(self) -> None:
        review = build_review()
        del review["pull_request"]
        self.assertNotIn("Pull request", self.render(review))

    def test_links_the_pull_request_when_present(self) -> None:
        self.assertIn('href="https://github.com/octo/repo/pull/12"',
                      self.render(build_review()))

    def test_renders_overall_comments_as_markdown(self) -> None:
        self.assertIn("<strong>missing</strong>", self.render(build_review()))

    def test_uses_the_given_timestamp(self) -> None:
        self.assertIn(GENERATED_AT, self.render(build_review()))

    def test_names_an_unknown_placeholder(self) -> None:
        with self.assertRaisesRegex(ValueError, "no_such_placeholder"):
            render_html_report(build_review(), "<p>${no_such_placeholder}</p>", GENERATED_AT)

    def test_rejects_a_stray_dollar_in_the_template(self) -> None:
        with self.assertRaises(ValueError):
            render_html_report(build_review(), "<p>costs $5</p>", GENERATED_AT)


def write_checkout(directory: str, files: dict[str, str]) -> pathlib.Path:
    """Create the given files under directory and return it as the checkout root."""
    root = pathlib.Path(directory)
    for relative_path, content in files.items():
        file_path = root / relative_path
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content, encoding="utf-8")
    return root


class CheckReviewTest(unittest.TestCase):
    """check_review lists the mistakes a schema-valid review can still carry."""

    def check(self, review: dict[str, Any], files: dict[str, str] | None = None) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, files or {"src/main/index.ts": "x\n" * 40})
            return check_review(review, root)

    def test_accepts_a_consistent_review(self) -> None:
        self.assertEqual(self.check(build_review()), [])

    def test_rejects_an_id_whose_prefix_is_not_the_category_number(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [build_finding(id="3-1")]},
        ])
        self.assertTrue(any("3-1" in problem and "category 2" in problem
                            for problem in self.check(review)))

    def test_rejects_ids_that_skip_a_number(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(id="2-1"), build_finding(id="2-3")]},
        ])
        self.assertTrue(any("2-3" in problem and "2-2" in problem
                            for problem in self.check(review)))

    def test_rejects_a_path_that_is_not_in_the_checkout(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(path="src/missing.ts")]},
        ])
        self.assertTrue(any("src/missing.ts" in problem for problem in self.check(review)))

    def test_rejects_an_absolute_path(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(path="/etc/passwd")]},
        ])
        self.assertTrue(any("absolute" in problem for problem in self.check(review)))

    def test_rejects_a_line_past_the_end_of_the_file(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [build_finding(line=41)]},
        ])
        self.assertTrue(any("41" in problem and "40" in problem
                            for problem in self.check(review)))

    def test_rejects_a_line_without_a_path(self) -> None:
        finding = build_finding()
        del finding["path"]
        review = build_review(categories=[
            {"number": 2, "name": "Security", "findings": [finding]},
        ])
        self.assertTrue(any("line" in problem and "path" in problem
                            for problem in self.check(review)))

    def test_rejects_an_unterminated_code_fence(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(body="```ts\nlet x;")]},
        ])
        self.assertTrue(any("fence" in problem for problem in self.check(review)))

    def test_rejects_a_blank_title_or_body(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(title="  ", body="")]},
        ])
        problems = self.check(review)
        self.assertTrue(any("title" in problem for problem in problems))
        self.assertTrue(any("body" in problem for problem in problems))

    def test_rejects_a_stale_placeholder_title(self) -> None:
        review = build_review(title="Code Review: [branch description]")
        self.assertTrue(any("placeholder" in problem for problem in self.check(review)))


class WriteReportsTest(unittest.TestCase):
    """write_reports writes both files into the output directory."""

    def test_writes_the_markdown_and_html_reports(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_dir = pathlib.Path(directory)
            written = write_reports(build_review(), output_dir, read_template(), GENERATED_AT)
            self.assertEqual(
                [path.name for path in written], [MARKDOWN_REPORT_NAME, HTML_REPORT_NAME]
            )
            self.assertTrue((output_dir / MARKDOWN_REPORT_NAME).exists())
            self.assertTrue((output_dir / HTML_REPORT_NAME).exists())

    def test_overwrites_an_existing_report(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_dir = pathlib.Path(directory)
            (output_dir / MARKDOWN_REPORT_NAME).write_text("stale", encoding="utf-8")
            write_reports(build_review(), output_dir, read_template(), GENERATED_AT)
            self.assertNotEqual(
                (output_dir / MARKDOWN_REPORT_NAME).read_text(encoding="utf-8"), "stale"
            )


class MainTest(unittest.TestCase):
    """main reports errors on stderr and the written paths on stdout."""

    def test_returns_one_for_malformed_json(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            review_path = pathlib.Path(directory) / "review.json"
            review_path.write_text("{", encoding="utf-8")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                status = render_review.main([str(review_path), "--output-dir", directory])
            self.assertEqual(status, 1)
            self.assertTrue(stderr.getvalue().startswith("error:"))

    def test_writes_into_the_output_directory_and_reports_the_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, {"src/main/index.ts": "x\n" * 40})
            review_path = root / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                status = render_review.main(
                    [str(review_path), "--output-dir", directory, "--root", directory]
                )
            self.assertEqual(status, 0)
            self.assertTrue((pathlib.Path(directory) / HTML_REPORT_NAME).exists())
            self.assertIn(f"wrote {directory}/{MARKDOWN_REPORT_NAME}", stdout.getvalue())
            self.assertIn("1 finding in 1 category", stdout.getvalue())

    def test_refuses_to_write_when_the_check_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, {})
            review_path = root / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            stderr = io.StringIO()
            with contextlib.redirect_stderr(stderr):
                status = render_review.main(
                    [str(review_path), "--output-dir", directory, "--root", directory]
                )
            self.assertEqual(status, 1)
            self.assertIn("src/main/index.ts", stderr.getvalue())
            self.assertFalse((root / HTML_REPORT_NAME).exists())

    def test_check_only_reports_and_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = write_checkout(directory, {"src/main/index.ts": "x\n" * 40})
            review_path = root / "review.json"
            review_path.write_text(json.dumps(build_review()), encoding="utf-8")
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                status = render_review.main(
                    [str(review_path), "--check", "--output-dir", directory, "--root", directory]
                )
            self.assertEqual(status, 0)
            self.assertIn("OK", stdout.getvalue())
            self.assertFalse((root / HTML_REPORT_NAME).exists())


if __name__ == "__main__":
    unittest.main()
