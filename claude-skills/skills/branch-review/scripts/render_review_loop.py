#!/usr/bin/env python3
"""Render every review pass of a branch-review-loop run into one REVIEW.md and REVIEW.html.

branch-review-loop reviews, fixes, and reviews again, and each pass writes its
own review.json. Rendering only the latest pass would drop the findings the
loop already fixed, so this script takes every pass in order and writes one
report pair in which each finding carries the iteration that raised it and
whether the loop has fixed it since.

Each iteration gets one status:

  - "fixed": every iteration but the last, because the loop fixes a pass's
    findings before it runs the next pass.
  - "open": the last iteration, until the loop fixes its findings.
  - "fixed-unverified": the last iteration once the loop passes --latest-fixed,
    which it does after a fix pass that no later review follows.
  - "clean": an iteration that raised no finding.

The review files are validated for shape but not re-checked against the
checkout: a fix shortens or deletes the lines an earlier finding pointed at,
so those anchors are history rather than errors. render_review.py checked
each file when the pass wrote it.

Usage:
    render_review_loop.py iteration-1/review.json iteration-2/review.json
    render_review_loop.py iteration-1/review.json --latest-fixed
    render_review_loop.py ... --output-dir DIR

Run from anywhere inside the repository checkout unless --output-dir is given.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from render_review import (
    HTML_REPORT_NAME,
    MARKDOWN_REPORT_NAME,
    NO_FINDINGS_TEXT,
    TEMPLATE_PATH,
    count_findings,
    escape_html,
    find_repository_root,
    format_count,
    format_finding_heading,
    format_location,
    format_metadata_bullets,
    format_summary,
    list_nonempty_categories,
    load_review,
    read_template,
    render_chip,
    render_markdown_subset,
    render_meta_rows,
    substitute_template,
)

STATUS_FIXED = "fixed"
STATUS_OPEN = "open"
STATUS_FIXED_UNVERIFIED = "fixed-unverified"
STATUS_CLEAN = "clean"

STATUS_LABELS = {
    STATUS_FIXED: "Fixed",
    STATUS_OPEN: "Open",
    STATUS_FIXED_UNVERIFIED: "Fixed (not re-reviewed)",
    STATUS_CLEAN: "Clean",
}
# Lower-case wording for the REVIEW.md headings and the console summary.
STATUS_PHRASES = {
    STATUS_FIXED: "fixed",
    STATUS_OPEN: "open",
    STATUS_FIXED_UNVERIFIED: "fixed, not re-reviewed",
    STATUS_CLEAN: "clean",
}

LOOP_SUMMARY_HEADER_CELLS = (
    "<th>ID</th><th>Iteration</th><th>Category</th><th>Location</th><th>Title</th>"
    "<th>Status</th>"
)


@dataclass(frozen=True)
class Iteration:
    """One review pass of the loop, numbered from 1 in the order it ran."""

    number: int
    review: dict[str, Any]
    status: str


def resolve_status(index: int, iteration_count: int, review: dict[str, Any],
                   is_latest_fixed: bool) -> str:
    """Return the status of the review at index among iteration_count passes."""
    if count_findings(review) == 0:
        return STATUS_CLEAN
    if index < iteration_count - 1:
        return STATUS_FIXED
    return STATUS_FIXED_UNVERIFIED if is_latest_fixed else STATUS_OPEN


def build_iterations(reviews: Sequence[dict[str, Any]],
                     is_latest_fixed: bool = False) -> list[Iteration]:
    """Return the reviews as numbered iterations, each with its status."""
    if not reviews:
        raise ValueError("a review loop needs at least one review file")
    return [
        Iteration(index + 1, review, resolve_status(index, len(reviews), review, is_latest_fixed))
        for index, review in enumerate(reviews)
    ]


def describe_iteration(iteration: Iteration) -> str:
    """Return "1 finding in 1 category (fixed)" or the no-findings sentence."""
    if iteration.status == STATUS_CLEAN:
        return NO_FINDINGS_TEXT
    return f"{format_summary(iteration.review)} ({STATUS_PHRASES[iteration.status]})"


def format_anchor(iteration: Iteration, finding: dict[str, Any]) -> str:
    """Return the page anchor of a finding, unique across iterations.

    The value goes straight into an id and an href attribute, and this script
    skips check_review, which is what checks the id format, so escaping here
    keeps a hand-edited review.json from breaking out of the attribute.
    """
    return escape_html(f"finding-i{iteration.number}-{finding['id']}")


def render_iteration_markdown(iteration: Iteration) -> list[str]:
    """Return the REVIEW.md lines of one iteration, headings nested one level down."""
    review = iteration.review
    if iteration.status == STATUS_CLEAN:
        return [f"## Iteration {iteration.number} (clean)", "", NO_FINDINGS_TEXT, ""]
    finding_count = format_count(count_findings(review), "finding", "findings")
    lines = [
        f"## Iteration {iteration.number} ({finding_count}, {STATUS_PHRASES[iteration.status]})",
        "",
    ]
    overall_comments = review.get("overall_comments", "").strip()
    if overall_comments:
        lines += ["### Overall Comments", "", overall_comments, ""]
    for category in list_nonempty_categories(review):
        lines += [f"### {category['number']}. {category['name']}", ""]
        for finding in category["findings"]:
            lines += ["#" + format_finding_heading(finding), "", finding["body"].strip(), ""]
    return lines


def render_loop_markdown_report(iterations: Sequence[Iteration]) -> str:
    """Return the REVIEW.md text covering every iteration, latest metadata first."""
    latest = iterations[-1].review
    parts = [f"# {latest['title']}", ""]
    parts += format_metadata_bullets(latest)
    parts += [f"- Iterations: {len(iterations)}", ""]
    parts += ["## Iterations", "", "| Iteration | Findings | Status |", "| --- | --- | --- |"]
    for iteration in iterations:
        parts.append(
            f"| {iteration.number} | {count_findings(iteration.review)} | "
            f"{STATUS_LABELS[iteration.status]} |"
        )
    parts.append("")
    for iteration in iterations:
        parts += ["---", ""] + render_iteration_markdown(iteration)
    return "\n".join(parts)


def render_status_badge(status: str) -> str:
    """Return the status as a small labelled badge."""
    return f'<span class="status status-{status}">{escape_html(STATUS_LABELS[status])}</span>'


def render_loop_meta_rows(iterations: Sequence[Iteration]) -> str:
    """Return the latest iteration's metadata rows plus the iteration count."""
    rows = render_meta_rows(iterations[-1].review)
    return f"{rows}\n<dt>Iterations</dt><dd>{len(iterations)}</dd>"


def render_loop_category_chips(iterations: Sequence[Iteration]) -> str:
    """Return one chip per category, counting findings across every iteration."""
    finding_counts: dict[int, int] = {}
    category_names: dict[int, str] = {}
    for iteration in iterations:
        for category in list_nonempty_categories(iteration.review):
            category_number = category["number"]
            finding_counts[category_number] = (
                finding_counts.get(category_number, 0) + len(category["findings"])
            )
            category_names.setdefault(category_number, category["name"])
    chips = [render_chip("category", "", "All", sum(finding_counts.values()))]
    chips += [
        render_chip("category", category_number, category_names[category_number],
                    finding_counts[category_number])
        for category_number in sorted(finding_counts)
    ]
    return "\n".join(chips)


def render_iteration_chips(iterations: Sequence[Iteration]) -> str:
    """Return a second chip group that narrows the page to one iteration."""
    total_findings = sum(count_findings(iteration.review) for iteration in iterations)
    chips = [render_chip("iteration", "", "All iterations", total_findings)]
    chips += [
        render_chip("iteration", iteration.number, f"Iteration {iteration.number}",
                    count_findings(iteration.review))
        for iteration in iterations
    ]
    return '<div class="chips">\n' + "\n".join(chips) + "\n</div>"


def render_loop_summary_rows(iterations: Sequence[Iteration]) -> str:
    """Return the table-of-contents rows for every finding of every iteration."""
    rows: list[str] = []
    for iteration in iterations:
        for category in list_nonempty_categories(iteration.review):
            for finding in category["findings"]:
                location = format_location(finding)
                location_html = f"<code>{escape_html(location)}</code>" if location else ""
                rows.append(
                    f'<tr data-category="{category["number"]}" '
                    f'data-iteration="{iteration.number}" '
                    f'data-path="{escape_html(finding.get("path", ""))}">'
                    f'<td><a href="#{format_anchor(iteration, finding)}">'
                    f"{escape_html(finding['id'])}</a></td>"
                    f"<td>{iteration.number}</td>"
                    f"<td>{escape_html(category['name'])}</td>"
                    f'<td class="location">{location_html}</td>'
                    f"<td>{escape_html(finding['title'])}</td>"
                    f"<td>{render_status_badge(iteration.status)}</td></tr>"
                )
    return "\n".join(rows)


def render_loop_finding_card(iteration: Iteration, category: dict[str, Any],
                             finding: dict[str, Any]) -> str:
    """Return one finding as a <details> card, open only while the finding is open.

    Fixed findings are history the reader scrolls past, so they start collapsed.
    """
    location = format_location(finding)
    location_html = f'<span class="location">{escape_html(location)}</span>' if location else ""
    open_attribute = " open" if iteration.status == STATUS_OPEN else ""
    return (
        f'<details class="finding" id="{format_anchor(iteration, finding)}" '
        f'data-category="{category["number"]}" data-iteration="{iteration.number}" '
        f'data-path="{escape_html(finding.get("path", ""))}"{open_attribute}>\n'
        f"<summary>{escape_html(finding['id'])}. {escape_html(finding['title'])}"
        f"{render_status_badge(iteration.status)}{location_html}</summary>\n"
        f'<div class="body">\n{render_markdown_subset(finding["body"])}\n</div>\n'
        "</details>"
    )


def render_iteration_section(iteration: Iteration) -> str:
    """Return one <section> per iteration: its overall comments, then its categories."""
    review = iteration.review
    heading = (
        f"<h2>Iteration {iteration.number} "
        f'<span class="count">{count_findings(review)}</span>'
        f"{render_status_badge(iteration.status)}</h2>"
    )
    parts = [f'<section class="iteration" data-iteration="{iteration.number}">', heading]
    if iteration.status == STATUS_CLEAN:
        parts.append(f'<p class="clean-iteration">{escape_html(NO_FINDINGS_TEXT)}</p>')
    overall_html = render_markdown_subset(review.get("overall_comments", ""))
    if overall_html:
        parts.append(
            f'<section class="overall">\n<h3>Overall Comments</h3>\n{overall_html}\n</section>'
        )
    for category in list_nonempty_categories(review):
        cards = "\n".join(
            render_loop_finding_card(iteration, category, finding)
            for finding in category["findings"]
        )
        parts.append(
            f'<section data-category="{category["number"]}" '
            f'data-iteration="{iteration.number}">\n'
            f"<h3>{category['number']}. {escape_html(category['name'])} "
            f'<span class="count">{len(category["findings"])}</span></h3>\n'
            f"{cards}\n</section>"
        )
    parts.append("</section>")
    return "\n".join(parts)


def build_loop_template_values(
    iterations: Sequence[Iteration], generated_at: str
) -> dict[str, str]:
    """Return every placeholder the template expects, already escaped."""
    latest = iterations[-1].review
    total_findings = sum(count_findings(iteration.review) for iteration in iterations)
    language = latest.get("language")
    return {
        "title": escape_html(latest["title"]),
        "lang_attribute": f' lang="{escape_html(language)}"' if language else "",
        "no_findings_text": escape_html(NO_FINDINGS_TEXT),
        "meta_rows": render_loop_meta_rows(iterations),
        "finding_count": str(total_findings),
        "category_chips": render_loop_category_chips(iterations),
        "iteration_chips": render_iteration_chips(iterations),
        "summary_header": LOOP_SUMMARY_HEADER_CELLS,
        "summary_rows": render_loop_summary_rows(iterations),
        # Each iteration carries its own overall comments inside its section.
        "overall_section": "",
        "sections": "\n\n".join(render_iteration_section(iteration) for iteration in iterations),
        "report_state": "has-findings" if total_findings else "no-findings",
        "generated_at": escape_html(generated_at),
    }


def render_loop_html_report(iterations: Sequence[Iteration], template_text: str,
                            generated_at: str) -> str:
    """Return the HTML page with every iteration injected into the shared template."""
    return substitute_template(template_text, build_loop_template_values(iterations, generated_at))


def write_loop_reports(iterations: Sequence[Iteration], output_dir: Path,
                       template_text: str, generated_at: str) -> list[Path]:
    """Write REVIEW.md and REVIEW.html into output_dir and return their paths."""
    markdown_path = output_dir / MARKDOWN_REPORT_NAME
    html_path = output_dir / HTML_REPORT_NAME
    # Render both before writing either, so a template error cannot leave a
    # fresh REVIEW.md next to a stale REVIEW.html.
    markdown_text = render_loop_markdown_report(iterations)
    html_text = render_loop_html_report(iterations, template_text, generated_at)
    markdown_path.write_text(markdown_text, encoding="utf-8")
    html_path.write_text(html_text, encoding="utf-8")
    return [markdown_path, html_path]


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    """Parse the command line."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("reviews", nargs="+", help="review.json of each iteration, oldest first")
    parser.add_argument(
        "--latest-fixed",
        action="store_true",
        help="the loop fixed the findings of the last review without reviewing again",
    )
    parser.add_argument(
        "--output-dir", help="directory to write into (default: the repository root)"
    )
    parser.add_argument("--template", help=f"HTML template to use (default: {TEMPLATE_PATH})")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    generated_at = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    try:
        reviews = [load_review(Path(review_path)) for review_path in args.reviews]
        iterations = build_iterations(reviews, is_latest_fixed=args.latest_fixed)
        output_dir = Path(args.output_dir) if args.output_dir else find_repository_root()
        template_text = read_template(Path(args.template) if args.template else TEMPLATE_PATH)
        written = write_loop_reports(iterations, output_dir, template_text, generated_at)
    except (ValueError, OSError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for path in written:
        print(f"wrote {path}")
    for iteration in iterations:
        print(f"iteration {iteration.number}: {describe_iteration(iteration)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
