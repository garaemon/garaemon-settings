"""Tests for rendering every iteration of a review loop into one report pair.

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

import render_review_loop
from render_review import HTML_REPORT_NAME, MARKDOWN_REPORT_NAME, NO_FINDINGS_TEXT, read_template
from render_review_loop import (
    STATUS_CLEAN,
    STATUS_FIXED,
    STATUS_FIXED_UNVERIFIED,
    STATUS_OPEN,
    build_iterations,
    render_loop_html_report,
    render_loop_markdown_report,
    write_loop_reports,
)

GENERATED_AT = "2026-09-18 10:00 UTC"


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


def build_clean_review(**overrides: Any) -> dict[str, Any]:
    """Return a review whose every category is empty."""
    return build_review(
        categories=[{"number": 2, "name": "Security", "findings": []}],
        overall_comments="",
        **overrides,
    )


def build_second_review(**overrides: Any) -> dict[str, Any]:
    """Return a review with one Naming finding, as a second iteration would raise."""
    review = build_review(
        stats={"files": 3, "additions": 130, "deletions": 8},
        overall_comments="",
        categories=[{
            "number": 3,
            "name": "Naming",
            "findings": [build_finding(id="3-1", title="Rename btn to submitButton", line=12)],
        }],
    )
    review.update(overrides)
    return review


class BuildIterationsTest(unittest.TestCase):
    """build_iterations numbers the reviews and assigns each a status."""

    def test_should_number_iterations_from_one_in_argument_order(self) -> None:
        iterations = build_iterations([build_review(), build_second_review()])
        self.assertEqual([iteration.number for iteration in iterations], [1, 2])

    def test_should_mark_every_iteration_before_the_latest_fixed(self) -> None:
        iterations = build_iterations([build_review(), build_second_review()])
        self.assertEqual(iterations[0].status, STATUS_FIXED)

    def test_should_mark_the_latest_iteration_open_by_default(self) -> None:
        iterations = build_iterations([build_review(), build_second_review()])
        self.assertEqual(iterations[1].status, STATUS_OPEN)

    def test_should_mark_the_latest_iteration_unverified_when_the_loop_fixed_it(self) -> None:
        iterations = build_iterations([build_review()], is_latest_fixed=True)
        self.assertEqual(iterations[0].status, STATUS_FIXED_UNVERIFIED)

    def test_should_mark_an_iteration_without_findings_clean(self) -> None:
        iterations = build_iterations([build_review(), build_clean_review()])
        self.assertEqual(iterations[1].status, STATUS_CLEAN)

    def test_should_reject_an_empty_list(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least one"):
            build_iterations([])


class RenderLoopMarkdownReportTest(unittest.TestCase):
    """render_loop_markdown_report writes one REVIEW.md covering every iteration."""

    def render(self, reviews: list[dict[str, Any]], **options: Any) -> str:
        return render_loop_markdown_report(build_iterations(reviews, **options))

    def test_should_start_with_the_latest_title(self) -> None:
        report = self.render([build_review(), build_second_review(title="Code Review: later")])
        self.assertTrue(report.startswith("# Code Review: later\n"))

    def test_should_list_the_iteration_count_with_the_metadata(self) -> None:
        report = self.render([build_review(), build_second_review()])
        self.assertIn("- Iterations: 2\n", report)

    def test_should_take_the_change_size_from_the_latest_iteration(self) -> None:
        report = self.render([build_review(), build_second_review()])
        self.assertIn("- Changes: 3 files changed, 130 insertions, 8 deletions\n", report)

    def test_should_give_every_iteration_its_own_heading(self) -> None:
        report = self.render([build_review(), build_second_review()])
        self.assertIn("\n## Iteration 1", report)
        self.assertIn("\n## Iteration 2", report)

    def test_should_state_the_status_in_the_iteration_heading(self) -> None:
        report = self.render([build_review(), build_second_review()])
        self.assertIn("## Iteration 1 (1 finding, fixed)", report)
        self.assertIn("## Iteration 2 (1 finding, open)", report)

    def test_should_nest_category_and_finding_headings_under_the_iteration(self) -> None:
        report = self.render([build_review()])
        self.assertIn("\n### 2. Security\n", report)
        self.assertIn(
            "\n#### 2-1. [src/main/index.ts:29] IPC color inputs not validated\n", report
        )

    def test_should_keep_the_overall_comments_of_each_iteration(self) -> None:
        report = self.render([build_review()])
        self.assertIn("\n### Overall Comments\n\nDocumentation is **missing** throughout.", report)

    def test_should_say_no_findings_for_a_clean_iteration(self) -> None:
        report = self.render([build_review(), build_clean_review()])
        self.assertIn(f"## Iteration 2 (clean)\n\n{NO_FINDINGS_TEXT}\n", report)

    def test_should_keep_the_finding_body_verbatim(self) -> None:
        review = build_review(categories=[
            {"number": 2, "name": "Security",
             "findings": [build_finding(body="```ts\nlet x;\n```")]},
        ])
        self.assertIn("```ts\nlet x;\n```", self.render([review]))


class RenderLoopHtmlReportTest(unittest.TestCase):
    """render_loop_html_report fills the shared template with every iteration."""

    def setUp(self) -> None:
        self.template_text = read_template()

    def render(self, reviews: list[dict[str, Any]], **options: Any) -> str:
        iterations = build_iterations(reviews, **options)
        return render_loop_html_report(iterations, self.template_text, GENERATED_AT)

    def test_should_prefix_every_anchor_with_its_iteration(self) -> None:
        page = self.render([build_review(), build_second_review()])
        self.assertIn('href="#finding-i1-2-1"', page)
        self.assertIn('id="finding-i1-2-1"', page)
        self.assertIn('href="#finding-i2-3-1"', page)
        self.assertIn('id="finding-i2-3-1"', page)

    def test_should_tag_rows_and_cards_with_their_iteration(self) -> None:
        page = self.render([build_review(), build_second_review()])
        self.assertIn('<tr data-category="3" data-iteration="2"', page)
        self.assertIn('data-category="3" data-iteration="2" data-path="src/main/index.ts"', page)

    def test_should_offer_one_chip_per_iteration(self) -> None:
        page = self.render([build_review(), build_second_review()])
        self.assertIn('data-filter-key="iteration" data-filter-value="1"', page)
        self.assertIn('data-filter-key="iteration" data-filter-value="2"', page)

    def test_should_count_findings_across_iterations_on_the_category_chips(self) -> None:
        page = self.render([build_review(), build_review()])
        self.assertIn("Security <b>2</b>", page)

    def test_should_add_iteration_and_status_columns_to_the_summary_table(self) -> None:
        page = self.render([build_review()])
        self.assertIn("<th>Iteration</th>", page)
        self.assertIn("<th>Status</th>", page)

    def test_should_label_fixed_and_open_findings(self) -> None:
        page = self.render([build_review(), build_second_review()])
        self.assertIn('class="status status-fixed">Fixed<', page)
        self.assertIn('class="status status-open">Open<', page)

    def test_should_label_findings_fixed_without_a_later_review(self) -> None:
        page = self.render([build_review()], is_latest_fixed=True)
        self.assertIn('class="status status-fixed-unverified">Fixed (not re-reviewed)<', page)

    def test_should_collapse_fixed_cards_and_open_the_open_ones(self) -> None:
        page = self.render([build_review(), build_second_review()])
        self.assertIn('id="finding-i1-2-1" data-category="2" data-iteration="1" '
                      'data-path="src/main/index.ts">', page)
        self.assertIn('id="finding-i2-3-1" data-category="3" data-iteration="2" '
                      'data-path="src/main/index.ts" open>', page)

    def test_should_wrap_each_iteration_in_its_own_section(self) -> None:
        page = self.render([build_review(), build_clean_review()])
        self.assertIn('<section class="iteration" data-iteration="1">', page)
        self.assertIn('<section class="iteration" data-iteration="2">', page)

    def test_should_say_no_findings_inside_a_clean_iteration(self) -> None:
        page = self.render([build_review(), build_clean_review()])
        self.assertIn(f'<p class="clean-iteration">{NO_FINDINGS_TEXT}</p>', page)

    def test_should_render_the_overall_comments_of_each_iteration(self) -> None:
        self.assertIn("<strong>missing</strong>", self.render([build_review()]))

    def test_should_show_the_iteration_count_in_the_metadata(self) -> None:
        self.assertIn("<dt>Iterations</dt><dd>2</dd>",
                      self.render([build_review(), build_second_review()]))

    def test_should_mark_the_page_as_having_findings_when_any_iteration_has_one(self) -> None:
        page = self.render([build_review(), build_clean_review()])
        self.assertIn('class="has-findings"', page)

    def test_should_mark_the_page_as_having_no_findings_when_every_iteration_is_clean(self) -> None:
        self.assertIn('class="no-findings"', self.render([build_clean_review()]))

    def test_should_leave_no_placeholder_or_dollar_behind(self) -> None:
        self.assertNotIn("$", self.render([build_review(), build_second_review()]))

    def test_should_escape_html_in_the_title_and_category_name(self) -> None:
        review = build_review(
            title="<script>alert(1)</script>",
            categories=[{"number": 2, "name": "<b>Security</b>", "findings": [build_finding()]}],
        )
        page = self.render([review])
        self.assertNotIn("<script>alert", page)
        self.assertNotIn("<b>Security</b>", page)


class WriteLoopReportsTest(unittest.TestCase):
    """write_loop_reports writes REVIEW.md and REVIEW.html side by side."""

    def test_should_write_both_reports_into_the_output_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output_dir = pathlib.Path(directory)
            written = write_loop_reports(
                build_iterations([build_review()]), output_dir, read_template(), GENERATED_AT
            )
            self.assertEqual(
                written, [output_dir / MARKDOWN_REPORT_NAME, output_dir / HTML_REPORT_NAME]
            )
            self.assertIn("## Iteration 1", (output_dir / MARKDOWN_REPORT_NAME).read_text())
            self.assertIn("finding-i1-2-1", (output_dir / HTML_REPORT_NAME).read_text())


class MainTest(unittest.TestCase):
    """main renders the files named on the command line and reports each iteration."""

    def run_main(self, reviews: list[dict[str, Any]], *extra_args: str) -> tuple[int, str, str]:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            review_paths: list[str] = []
            for index, review in enumerate(reviews, start=1):
                review_path = root / f"iteration-{index}" / "review.json"
                review_path.parent.mkdir()
                review_path.write_text(json.dumps(review), encoding="utf-8")
                review_paths.append(str(review_path))
            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                status = render_review_loop.main(
                    [*review_paths, "--output-dir", str(root), *extra_args]
                )
            return status, stdout.getvalue(), stderr.getvalue()

    def test_should_report_each_iteration_with_its_status(self) -> None:
        status, stdout, _ = self.run_main([build_review(), build_second_review()])
        self.assertEqual(status, 0)
        self.assertIn("iteration 1: 1 finding in 1 category (fixed)\n", stdout)
        self.assertIn("iteration 2: 1 finding in 1 category (open)\n", stdout)

    def test_should_print_the_no_findings_sentence_for_a_clean_iteration(self) -> None:
        _, stdout, _ = self.run_main([build_review(), build_clean_review()])
        self.assertIn(f"iteration 2: {NO_FINDINGS_TEXT}\n", stdout)

    def test_should_honor_the_latest_fixed_flag(self) -> None:
        _, stdout, _ = self.run_main([build_review()], "--latest-fixed")
        self.assertIn("iteration 1: 1 finding in 1 category (fixed, not re-reviewed)\n", stdout)

    def test_should_fail_on_a_review_that_does_not_validate(self) -> None:
        status, _, stderr = self.run_main([{"title": "no categories"}])
        self.assertEqual(status, 1)
        self.assertIn("categories", stderr)


if __name__ == "__main__":
    unittest.main()
