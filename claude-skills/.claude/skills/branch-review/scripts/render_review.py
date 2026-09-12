#!/usr/bin/env python3
"""Render a review.json file into REVIEW.md and REVIEW.html.

Both reports come from one JSON file so they never disagree, and the summary
at the top of the HTML page (finding counts per category, a table of contents
linking to every finding) is computed here rather than tallied by hand.

The review file lists findings grouped by the categories in SKILL.md:

    {
      "title": "Code Review: add color picker",
      "branch": "feature/color-picker",
      "range": "whole branch against main",
      "pull_request": "https://github.com/octo/repo/pull/12",
      "stats": {"files": 3, "additions": 120, "deletions": 8},
      "overall_comments": "Cross-cutting concerns, in markdown.",
      "categories": [
        {
          "number": 2,
          "name": "Security",
          "findings": [
            {
              "id": "2-1",
              "title": "IPC color inputs not validated",
              "path": "src/main/index.ts",
              "line": 29,
              "body": "Explanation in markdown, with ```code``` fences."
            }
          ]
        }
      ]
    }

"title" and "categories" are required, as are "id", "title" and "body" on every
finding. "path", "line", "pull_request", "stats" and "overall_comments" may be
left out. Bodies use a markdown subset: paragraphs, fenced code blocks, inline
code, **bold**, bullet and numbered lists, and > quotes.

Before writing anything the script checks the review for the mistakes a
schema-valid file can still carry: ids out of sequence, a path that is not in
the checkout, a line past the end of its file, an unterminated code fence, a
placeholder left in the title. It refuses to render while any remain, so the
reports never carry a broken anchor.

Usage:
    render_review.py review.json                   # check, then write into the repository root
    render_review.py review.json --check           # check only, write nothing
    render_review.py review.json --output-dir DIR  # write somewhere else

Run from anywhere inside the repository checkout.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from string import Template
from typing import Any

from commands import run_command

TEMPLATE_PATH = Path(__file__).resolve().parent.parent / "templates" / "review.html"
MARKDOWN_REPORT_NAME = "REVIEW.md"
HTML_REPORT_NAME = "REVIEW.html"
# branch-review-loop matches this exact sentence to decide the review is clean.
NO_FINDINGS_TEXT = "No findings."

FENCE_PATTERN = re.compile(r"^```(\w*)\s*$")
UNORDERED_ITEM_PATTERN = re.compile(r"^\s*[-*]\s+(.*)$")
ORDERED_ITEM_PATTERN = re.compile(r"^\s*\d+[.)]\s+(.*)$")
QUOTE_PATTERN = re.compile(r"^>\s?(.*)$")
CODE_SPAN_PATTERN = re.compile(r"(`[^`]*`)")
BOLD_PATTERN = re.compile(r"\*\*(.+?)\*\*")


@dataclass
class MarkdownBlock:
    """One block of the markdown subset: code, ulist, olist, quote or paragraph."""

    kind: str
    lines: list[str] = field(default_factory=list)
    language: str = ""


def load_review(review_path: Path) -> dict[str, Any]:
    """Read the review file and return it once it passes validation."""
    with open(review_path, encoding="utf-8") as handle:
        review = json.load(handle)
    validate_review(review)
    return review


def validate_review(review: Any) -> None:
    """Raise ValueError naming the first missing or ill-typed key."""
    if not isinstance(review, dict):
        raise ValueError("review must be a JSON object")
    if not isinstance(review.get("title"), str):
        raise ValueError("review is missing a string 'title'")
    if not isinstance(review.get("categories"), list):
        raise ValueError("review is missing a 'categories' list")
    seen_ids: set[str] = set()
    for category in review["categories"]:
        if not isinstance(category, dict):
            raise ValueError(f"category is not an object: {category!r}")
        if not isinstance(category.get("number"), int):
            raise ValueError(f"category is missing an integer 'number': {category!r}")
        if not isinstance(category.get("name"), str):
            raise ValueError(f"category is missing a string 'name': {category!r}")
        if not isinstance(category.get("findings"), list):
            raise ValueError(f"category {category['name']!r} is missing a 'findings' list")
        for finding in category["findings"]:
            validate_finding(finding)
            if finding["id"] in seen_ids:
                raise ValueError(f"finding id {finding['id']!r} is used more than once")
            seen_ids.add(finding["id"])


def validate_finding(finding: Any) -> None:
    """Raise ValueError when a finding lacks a required key or mistypes one."""
    if not isinstance(finding, dict):
        raise ValueError(f"finding is not an object: {finding!r}")
    for key in ("id", "title", "body"):
        if not isinstance(finding.get(key), str):
            raise ValueError(f"finding is missing a string {key!r}: {finding!r}")
    if "path" in finding and not isinstance(finding["path"], str):
        raise ValueError(f"finding {finding['id']!r} has a non-string 'path'")
    line = finding.get("line")
    if line is not None and (isinstance(line, bool) or not isinstance(line, int)):
        raise ValueError(f"finding {finding['id']!r} has a non-integer 'line'")


def list_nonempty_categories(review: dict[str, Any]) -> list[dict[str, Any]]:
    """Return the categories that carry at least one finding, in order."""
    return [category for category in review["categories"] if category["findings"]]


def count_findings(review: dict[str, Any]) -> int:
    """Return the number of findings across every category."""
    return sum(len(category["findings"]) for category in review["categories"])


def format_location(finding: dict[str, Any]) -> str:
    """Return "path:line", "path", or "" depending on what the finding names."""
    path = finding.get("path")
    if not path:
        return ""
    line = finding.get("line")
    return f"{path}:{line}" if line is not None else path


def check_review(review: dict[str, Any], root: Path) -> list[str]:
    """Return the problems a schema-valid review still has, empty when clean.

    root is the checkout the paths are relative to. Every message names the
    finding it concerns so the author can fix review.json without guessing.
    """
    problems = check_title(review["title"])
    for category in review["categories"]:
        for index, finding in enumerate(category["findings"], start=1):
            problems += check_finding_id(category, index, finding)
            problems += check_finding_text(finding)
            problems += check_finding_location(finding, root)
    if has_unterminated_fence(review.get("overall_comments", "")):
        problems.append("overall_comments has an unterminated ``` fence")
    return problems


def check_title(title: str) -> list[str]:
    """Return problems with the review title."""
    if not title.strip():
        return ["title is blank"]
    if "[branch description]" in title:
        return ["title still holds the placeholder '[branch description]'"]
    return []


def check_finding_id(category: dict[str, Any], index: int, finding: dict[str, Any]) -> list[str]:
    """Return problems with a finding id, which must be <category>-<index>."""
    expected = f"{category['number']}-{index}"
    if finding["id"] == expected:
        return []
    if not finding["id"].startswith(f"{category['number']}-"):
        return [
            f"finding {finding['id']} sits in category {category['number']} "
            f"({category['name']}); its id must start with '{category['number']}-'"
        ]
    return [f"finding {finding['id']} should be {expected}: ids run 1, 2, 3 within a category"]


def check_finding_text(finding: dict[str, Any]) -> list[str]:
    """Return problems with a finding's title and body."""
    problems: list[str] = []
    if not finding["title"].strip():
        problems.append(f"finding {finding['id']}: title is blank")
    if not finding["body"].strip():
        problems.append(f"finding {finding['id']}: body is blank")
    elif has_unterminated_fence(finding["body"]):
        problems.append(f"finding {finding['id']}: body has an unterminated ``` fence")
    return problems


def check_finding_location(finding: dict[str, Any], root: Path) -> list[str]:
    """Return problems with a finding's path and line, checked against root."""
    path = finding.get("path")
    line = finding.get("line")
    if path is None:
        if line is not None:
            return [f"finding {finding['id']}: line {line} is given without a path"]
        return []
    if Path(path).is_absolute():
        return [
            f"finding {finding['id']}: path {path} is absolute; "
            "use a path relative to the repository root"
        ]
    file_path = root / path
    if not file_path.is_file():
        return [f"finding {finding['id']}: path {path} does not exist in the checkout"]
    if line is None:
        return []
    line_count = count_lines(file_path)
    if line < 1 or line > line_count:
        return [
            f"finding {finding['id']}: line {line} is outside {path} ({line_count} lines)"
        ]
    return []


def has_unterminated_fence(text: str) -> bool:
    """Return whether the text opens a ``` fence it never closes."""
    fence_count = sum(1 for line in text.splitlines() if FENCE_PATTERN.match(line))
    return fence_count % 2 == 1


def count_lines(file_path: Path) -> int:
    """Return the number of lines in the file, tolerating non-UTF-8 bytes."""
    return len(file_path.read_text(encoding="utf-8", errors="replace").splitlines())


def escape_html(text: Any) -> str:
    """Return the text with HTML metacharacters, quotes included, escaped."""
    return html.escape(str(text), quote=True)


def render_inline_markdown(text: str) -> str:
    """Return one line of text as HTML with code spans and bold applied.

    Every token is escaped before any tag is added, so markup inside a code
    span or the running text can never reach the page as HTML.
    """
    rendered: list[str] = []
    for token in CODE_SPAN_PATTERN.split(text):
        if len(token) >= 2 and token.startswith("`") and token.endswith("`"):
            rendered.append(f"<code>{escape_html(token[1:-1])}</code>")
        else:
            rendered.append(BOLD_PATTERN.sub(r"<strong>\1</strong>", escape_html(token)))
    return "".join(rendered)


def collect_fenced_block(lines: Sequence[str], start: int) -> tuple[MarkdownBlock, int]:
    """Return the code block opened at lines[start] and the index after it.

    An unterminated fence runs to the end of the text rather than raising, so a
    typo in a review body degrades to a long code block instead of no report.
    """
    language = FENCE_PATTERN.match(lines[start]).group(1)
    block = MarkdownBlock("code", language=language)
    index = start + 1
    while index < len(lines) and not FENCE_PATTERN.match(lines[index]):
        block.lines.append(lines[index])
        index += 1
    return block, index + 1


def classify_line(line: str) -> tuple[str, str]:
    """Return (block kind, content) for one line outside a code fence."""
    if not line.strip():
        return "blank", ""
    unordered_match = UNORDERED_ITEM_PATTERN.match(line)
    if unordered_match:
        return "ulist", unordered_match.group(1)
    ordered_match = ORDERED_ITEM_PATTERN.match(line)
    if ordered_match:
        return "olist", ordered_match.group(1)
    quote_match = QUOTE_PATTERN.match(line)
    if quote_match:
        return "quote", quote_match.group(1)
    return "paragraph", line.rstrip()


def split_markdown_blocks(text: str) -> list[MarkdownBlock]:
    """Split markdown text into blocks; a blank line or a kind change ends one."""
    lines = text.splitlines()
    blocks: list[MarkdownBlock] = []
    current: MarkdownBlock | None = None
    index = 0
    while index < len(lines):
        if FENCE_PATTERN.match(lines[index]):
            current = None
            block, index = collect_fenced_block(lines, index)
            blocks.append(block)
            continue
        kind, content = classify_line(lines[index])
        index += 1
        if kind == "blank":
            current = None
            continue
        if current is None or current.kind != kind:
            current = MarkdownBlock(kind)
            blocks.append(current)
        current.lines.append(content)
    return blocks


def render_markdown_block(block: MarkdownBlock) -> str:
    """Return one block as HTML."""
    if block.kind == "code":
        class_attribute = f' class="language-{block.language}"' if block.language else ""
        return f"<pre><code{class_attribute}>{escape_html(chr(10).join(block.lines))}</code></pre>"
    if block.kind in ("ulist", "olist"):
        tag = "ul" if block.kind == "ulist" else "ol"
        items = "\n".join(f"<li>{render_inline_markdown(item)}</li>" for item in block.lines)
        return f"<{tag}>\n{items}\n</{tag}>"
    paragraph = f"<p>{render_inline_markdown(chr(10).join(block.lines))}</p>"
    if block.kind == "quote":
        return f"<blockquote>{paragraph}</blockquote>"
    return paragraph


def render_markdown_subset(text: str) -> str:
    """Return markdown text as HTML, or "" when the text is blank."""
    return "\n".join(render_markdown_block(block) for block in split_markdown_blocks(text))


def format_finding_heading(finding: dict[str, Any]) -> str:
    """Return the "### N-N. [path:line] Title" heading used in REVIEW.md."""
    location = format_location(finding)
    location_text = f"[{location}] " if location else ""
    return f"### {finding['id']}. {location_text}{finding['title']}"


def render_markdown_report(review: dict[str, Any]) -> str:
    """Return the REVIEW.md text in the structure SKILL.md describes."""
    parts = [f"# {review['title']}", ""]
    if review.get("branch"):
        parts.append(f"Branch: `{review['branch']}`")
    if review.get("range"):
        parts.append(f"Range: {review['range']}")
    if review.get("pull_request"):
        parts.append(f"Pull request: {review['pull_request']}")
    stats = review.get("stats")
    if stats:
        parts.append(
            f"{stats.get('files', 0)} files changed, {stats.get('additions', 0)} "
            f"insertions, {stats.get('deletions', 0)} deletions"
        )
    parts += ["", "## Overall Comments", "", review.get("overall_comments", "").strip(), ""]
    categories = list_nonempty_categories(review)
    if not categories:
        parts += ["---", "", NO_FINDINGS_TEXT, ""]
    for category in categories:
        parts += ["---", "", f"## {category['number']}. {category['name']}", ""]
        for finding in category["findings"]:
            parts += [format_finding_heading(finding), "", finding["body"].strip(), ""]
    return "\n".join(parts)


def read_template(template_path: Path = TEMPLATE_PATH) -> str:
    """Return the HTML template text."""
    return template_path.read_text(encoding="utf-8")


def render_meta_rows(review: dict[str, Any]) -> str:
    """Return the branch, range, pull request and size as <dt>/<dd> pairs."""
    rows: list[tuple[str, str]] = []
    if review.get("branch"):
        rows.append(("Branch", f"<code>{escape_html(review['branch'])}</code>"))
    if review.get("range"):
        rows.append(("Range", escape_html(review["range"])))
    if review.get("pull_request"):
        url = escape_html(review["pull_request"])
        rows.append(("Pull request", f'<a href="{url}">{url}</a>'))
    stats = review.get("stats")
    if stats:
        rows.append((
            "Changes",
            f"{escape_html(stats.get('files', 0))} files, "
            f"+{escape_html(stats.get('additions', 0))} / "
            f"-{escape_html(stats.get('deletions', 0))}",
        ))
    return "\n".join(f"<dt>{label}</dt><dd>{value}</dd>" for label, value in rows)


def render_category_chips(review: dict[str, Any]) -> str:
    """Return one filter chip per non-empty category, preceded by an "All" chip."""
    chips = [
        '<button type="button" class="chip active" data-category="">'
        f"All <b>{count_findings(review)}</b></button>"
    ]
    for category in list_nonempty_categories(review):
        chips.append(
            f'<button type="button" class="chip" data-category="{category["number"]}">'
            f"{escape_html(category['name'])} <b>{len(category['findings'])}</b></button>"
        )
    return "\n".join(chips)


def render_summary_rows(review: dict[str, Any]) -> str:
    """Return the table-of-contents rows, each linking to its finding card."""
    rows: list[str] = []
    for category in list_nonempty_categories(review):
        for finding in category["findings"]:
            location = format_location(finding)
            location_html = f"<code>{escape_html(location)}</code>" if location else ""
            rows.append(
                f'<tr data-category="{category["number"]}" '
                f'data-path="{escape_html(finding.get("path", ""))}">'
                f'<td><a href="#finding-{escape_html(finding["id"])}">'
                f"{escape_html(finding['id'])}</a></td>"
                f"<td>{escape_html(category['name'])}</td>"
                f'<td class="location">{location_html}</td>'
                f"<td>{escape_html(finding['title'])}</td></tr>"
            )
    return "\n".join(rows)


def render_finding_card(category: dict[str, Any], finding: dict[str, Any]) -> str:
    """Return one finding as an open <details> card."""
    location = format_location(finding)
    location_html = f'<span class="location">{escape_html(location)}</span>' if location else ""
    return (
        f'<details class="finding" id="finding-{escape_html(finding["id"])}" '
        f'data-category="{category["number"]}" '
        f'data-path="{escape_html(finding.get("path", ""))}" open>\n'
        f"<summary>{escape_html(finding['id'])}. {escape_html(finding['title'])}"
        f"{location_html}</summary>\n"
        f'<div class="body">\n{render_markdown_subset(finding["body"])}\n</div>\n'
        "</details>"
    )


def render_sections(review: dict[str, Any]) -> str:
    """Return one <section> per non-empty category, holding its finding cards."""
    sections: list[str] = []
    for category in list_nonempty_categories(review):
        cards = "\n".join(
            render_finding_card(category, finding) for finding in category["findings"]
        )
        sections.append(
            f'<section data-category="{category["number"]}">\n'
            f"<h2>{category['number']}. {escape_html(category['name'])} "
            f'<span class="count">{len(category["findings"])}</span></h2>\n'
            f"{cards}\n</section>"
        )
    return "\n\n".join(sections)


def build_template_values(review: dict[str, Any], generated_at: str) -> dict[str, str]:
    """Return every placeholder the template expects, already escaped."""
    finding_count = count_findings(review)
    return {
        "title": escape_html(review["title"]),
        "meta_rows": render_meta_rows(review),
        "finding_count": str(finding_count),
        "category_chips": render_category_chips(review),
        "summary_rows": render_summary_rows(review),
        "overall_comments": render_markdown_subset(review.get("overall_comments", "")),
        "sections": render_sections(review),
        "report_state": "has-findings" if finding_count else "no-findings",
        "generated_at": escape_html(generated_at),
    }


def render_html_report(review: dict[str, Any], template_text: str, generated_at: str) -> str:
    """Return the HTML page with the review injected into the template.

    Substitution is strict: an unknown placeholder or a stray "$" in the
    template raises ValueError instead of leaving a half-rendered page.
    """
    try:
        return Template(template_text).substitute(build_template_values(review, generated_at))
    except KeyError as error:
        raise ValueError(f"template references an unknown placeholder: {error.args[0]}") from error
    except ValueError as error:
        raise ValueError(f"template has a stray '$': {error}") from error


def find_repository_root() -> Path:
    """Return the root of the checkout the command runs in."""
    return Path(run_command(["git", "rev-parse", "--show-toplevel"]).strip())


def write_reports(
    review: dict[str, Any], output_dir: Path, template_text: str, generated_at: str
) -> list[Path]:
    """Write REVIEW.md and REVIEW.html into output_dir and return their paths."""
    markdown_path = output_dir / MARKDOWN_REPORT_NAME
    html_path = output_dir / HTML_REPORT_NAME
    markdown_path.write_text(render_markdown_report(review), encoding="utf-8")
    html_path.write_text(render_html_report(review, template_text, generated_at), encoding="utf-8")
    return [markdown_path, html_path]


def format_count(count: int, singular: str, plural: str) -> str:
    """Return "1 finding" or "3 findings" style text."""
    return f"{count} {singular if count == 1 else plural}"


def format_summary(review: dict[str, Any]) -> str:
    """Return "N findings in M categories" for the review."""
    return (
        f"{format_count(count_findings(review), 'finding', 'findings')} in "
        f"{format_count(len(list_nonempty_categories(review)), 'category', 'categories')}"
    )


def report_problems(review_path: Path, problems: Sequence[str]) -> None:
    """Print the check failures to stderr, one per line."""
    print(
        f"error: {review_path} has {format_count(len(problems), 'problem', 'problems')}; "
        "fix the file and run again:",
        file=sys.stderr,
    )
    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    """Parse the command line."""
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("review", help="path to review.json")
    parser.add_argument(
        "--check", action="store_true", help="check the review and write nothing"
    )
    parser.add_argument(
        "--output-dir", help="directory to write into (default: the repository root)"
    )
    parser.add_argument(
        "--root",
        help="checkout that finding paths are relative to (default: the repository root)",
    )
    parser.add_argument("--template", help=f"HTML template to use (default: {TEMPLATE_PATH})")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    generated_at = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    try:
        review = load_review(Path(args.review))
        root = Path(args.root) if args.root else find_repository_root()
        problems = check_review(review, root)
        if problems:
            report_problems(Path(args.review), problems)
            return 1
        if args.check:
            print(f"OK: {args.review} passes every check ({format_summary(review)})")
            return 0
        template_text = read_template(Path(args.template) if args.template else TEMPLATE_PATH)
        output_dir = Path(args.output_dir) if args.output_dir else root
        written = write_reports(review, output_dir, template_text, generated_at)
    except (ValueError, OSError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for path in written:
        print(f"wrote {path}")
    print(format_summary(review))
    return 0


if __name__ == "__main__":
    sys.exit(main())
