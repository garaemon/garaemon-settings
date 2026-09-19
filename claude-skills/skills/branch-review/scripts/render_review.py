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
      "language": "en",
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
finding. "path", "line", "pull_request", "language", "stats" and
"overall_comments" may be left out. "language" is the BCP 47 tag of the review
text and becomes the lang attribute of the HTML page. Bodies use a markdown
subset: paragraphs, fenced code blocks, inline code, **bold**, bullet and
numbered lists, and > quotes. Fences start at column 0, and lists stay flat
because a nested item renders as a sibling in the HTML.

Before writing anything the script checks the review for the mistakes a
schema-valid file can still carry: ids out of sequence, a path that is not in
the checkout, a line past the end of its file, an unterminated code fence, a
placeholder left in the title. It refuses to render while any remain, so the
reports never carry a broken anchor.

A finding whose body holds no fenced code block is rendered all the same, but
the script names it in a note, because a finding reads best next to the code
it concerns and the fix it proposes.

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
from typing import Any, NamedTuple

from commands import run_command

TEMPLATE_PATH = Path(__file__).resolve().parent.parent / "templates" / "review.html"
MARKDOWN_REPORT_NAME = "REVIEW.md"
HTML_REPORT_NAME = "REVIEW.html"
# branch-review-loop matches this exact sentence, in REVIEW.md and in the
# output of render_review_loop.py, to decide that a review pass is clean.
NO_FINDINGS_TEXT = "No findings."
SUMMARY_HEADER_CELLS = "<th>ID</th><th>Category</th><th>Location</th><th>Title</th>"

# CommonMark opens a fence with three or more backticks and lets the info
# string hold anything but a backtick, so `c++` opens a fence and a four
# backtick fence can quote a three backtick one. The first word is the language.
FENCE_PATTERN = re.compile(r"^(`{3,})([^`\s]*)[^`]*$")
INDENTED_FENCE_PATTERN = re.compile(r"^\s+```")
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
    if "language" in review and not isinstance(review["language"], str):
        raise ValueError("review has a non-string 'language'")
    if "overall_comments" in review and not isinstance(review["overall_comments"], str):
        raise ValueError("review has a non-string 'overall_comments'")
    if "stats" in review and not isinstance(review["stats"], dict):
        raise ValueError("review has a non-object 'stats'")
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
    problems += [
        f"overall_comments {problem}"
        for problem in describe_fence_problems(review.get("overall_comments", ""))
    ]
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
    else:
        problems += [
            f"finding {finding['id']}: body {problem}"
            for problem in describe_fence_problems(finding["body"])
        ]
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
    if not file_path.resolve().is_relative_to(root.resolve()):
        return [
            f"finding {finding['id']}: path {path} leaves the checkout; "
            "use a path relative to the repository root"
        ]
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


def describe_fence_problems(text: str) -> list[str]:
    """Return the fence mistakes in the text, each phrased to follow a subject."""
    scan = scan_fences(text)
    if scan.has_indented_fence:
        # An indented opening fence is not counted as one, so its closing
        # fence reads as an unclosed opening. Report only the real mistake.
        return ["has an indented ``` fence; start every fence at column 0"]
    if scan.is_unterminated:
        return ["has an unterminated ``` fence"]
    return []


def is_fence_close(line: str, opening_length: int) -> bool:
    """Return whether the line closes a fence opened with opening_length backticks.

    CommonMark closes a fence with a run of backticks at least as long as the
    opening run, indented by at most three spaces and followed by nothing, so
    a longer fence can quote a shorter one without ending early.
    """
    indent_width = len(line) - len(line.lstrip(" "))
    trimmed_line = line.strip()
    return (
        indent_width <= 3
        and len(trimmed_line) >= opening_length
        and set(trimmed_line) == {"`"}
    )


class FenceScan(NamedTuple):
    """What one pass over the fences of a markdown text found."""

    is_unterminated: bool
    has_indented_fence: bool


def scan_fences(text: str) -> FenceScan:
    """Return whether the text leaves a fence open or indents one outside a fence.

    An indented ``` line, typically a code block inside a list item, opens no
    fence for the renderer, which would break the block into inline code spans.
    """
    opening_length = 0
    has_indented_fence = False
    for line in text.splitlines():
        if opening_length:
            if is_fence_close(line, opening_length):
                opening_length = 0
            continue
        fence_match = FENCE_PATTERN.match(line)
        if fence_match:
            opening_length = len(fence_match.group(1))
        elif INDENTED_FENCE_PATTERN.match(line):
            has_indented_fence = True
    return FenceScan(is_unterminated=opening_length != 0, has_indented_fence=has_indented_fence)


def has_code_block(text: str) -> bool:
    """Return whether the markdown text opens at least one code fence."""
    return any(FENCE_PATTERN.match(line) for line in text.splitlines())


def list_findings_without_code(review: dict[str, Any]) -> list[str]:
    """Return the ids of findings whose body shows no fenced code block.

    An inline code span does not count: the reader needs the offending lines
    and, where one exists, the proposed replacement, not just a name.
    """
    return [
        finding["id"]
        for category in review["categories"]
        for finding in category["findings"]
        if not has_code_block(finding["body"])
    ]


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
    fence_match = FENCE_PATTERN.match(lines[start])
    opening_length = len(fence_match.group(1))
    block = MarkdownBlock("code", language=fence_match.group(2))
    index = start + 1
    while index < len(lines) and not is_fence_close(lines[index], opening_length):
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
        class_attribute = f' class="language-{escape_html(block.language)}"' if block.language else ""
        code_text = "\n".join(block.lines)
        return f"<pre><code{class_attribute}>{escape_html(code_text)}</code></pre>"
    if block.kind in ("ulist", "olist"):
        tag = "ul" if block.kind == "ulist" else "ol"
        items = "\n".join(f"<li>{render_inline_markdown(item)}</li>" for item in block.lines)
        return f"<{tag}>\n{items}\n</{tag}>"
    paragraph_text = "\n".join(block.lines)
    paragraph = f"<p>{render_inline_markdown(paragraph_text)}</p>"
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


def format_metadata_bullets(review: dict[str, Any]) -> list[str]:
    """Return the branch, range, pull request and change size as REVIEW.md bullets.

    A bullet per row keeps the rows apart in rendered Markdown, where
    consecutive lines would otherwise merge into one paragraph.
    """
    bullets: list[str] = []
    if review.get("branch"):
        bullets.append(f"- Branch: `{review['branch']}`")
    if review.get("range"):
        bullets.append(f"- Range: {review['range']}")
    if review.get("pull_request"):
        bullets.append(f"- Pull request: {review['pull_request']}")
    stats = review.get("stats")
    if stats:
        bullets.append(
            f"- Changes: {stats.get('files', 0)} files changed, "
            f"{stats.get('additions', 0)} insertions, {stats.get('deletions', 0)} deletions"
        )
    return bullets


def render_markdown_report(review: dict[str, Any]) -> str:
    """Return the REVIEW.md text in the structure SKILL.md describes."""
    parts = [f"# {review['title']}", ""]
    parts += format_metadata_bullets(review)
    overall_comments = review.get("overall_comments", "").strip()
    if overall_comments:
        parts += ["", "## Overall Comments", "", overall_comments, ""]
    else:
        parts.append("")
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
        # Escaping keeps the value inside the attribute but leaves a
        # javascript: scheme meaningful, so only web URLs become links.
        is_web_url = review["pull_request"].startswith(("http://", "https://"))
        rows.append(("Pull request", f'<a href="{url}">{url}</a>' if is_web_url else url))
    stats = review.get("stats")
    if stats:
        rows.append((
            "Changes",
            f"{escape_html(stats.get('files', 0))} files, "
            f"+{escape_html(stats.get('additions', 0))} / "
            f"-{escape_html(stats.get('deletions', 0))}",
        ))
    return "\n".join(f"<dt>{label}</dt><dd>{value}</dd>" for label, value in rows)


def render_chip(filter_key: str, filter_value: Any, label: str, count: int) -> str:
    """Return one filter chip; an empty filter_value is the group's "All" chip.

    The page script keeps one selected value per filter_key, so chips of one
    group toggle among themselves and never disturb another group.
    """
    class_attribute = "chip active" if filter_value == "" else "chip"
    return (
        f'<button type="button" class="{class_attribute}" data-filter-key="{filter_key}" '
        f'data-filter-value="{escape_html(filter_value)}">'
        f"{escape_html(label)} <b>{count}</b></button>"
    )


def render_category_chips(review: dict[str, Any]) -> str:
    """Return one filter chip per non-empty category, preceded by an "All" chip."""
    chips = [render_chip("category", "", "All", count_findings(review))]
    for category in list_nonempty_categories(review):
        chips.append(
            render_chip("category", category["number"], category["name"], len(category["findings"]))
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


def render_overall_section(review: dict[str, Any]) -> str:
    """Return the Overall Comments section, or "" when the review has none."""
    overall_html = render_markdown_subset(review.get("overall_comments", ""))
    if not overall_html:
        return ""
    return f'<section class="overall">\n<h2>Overall Comments</h2>\n{overall_html}\n</section>'


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
    language = review.get("language")
    return {
        "title": escape_html(review["title"]),
        "lang_attribute": f' lang="{escape_html(language)}"' if language else "",
        "no_findings_text": escape_html(NO_FINDINGS_TEXT),
        "meta_rows": render_meta_rows(review),
        "finding_count": str(finding_count),
        "category_chips": render_category_chips(review),
        # Iterations exist only on the review loop page, which fills these itself.
        "iteration_chips": "",
        "summary_header": SUMMARY_HEADER_CELLS,
        "summary_rows": render_summary_rows(review),
        "overall_section": render_overall_section(review),
        "sections": render_sections(review),
        "report_state": "has-findings" if finding_count else "no-findings",
        "generated_at": escape_html(generated_at),
    }


def substitute_template(template_text: str, values: dict[str, str]) -> str:
    """Return the template filled with values, naming what made it fail.

    Substitution is strict: an unknown placeholder or a stray "$" in the
    template raises ValueError instead of leaving a half-rendered page.
    """
    try:
        return Template(template_text).substitute(values)
    except KeyError as error:
        raise ValueError(f"template references an unknown placeholder: {error.args[0]}") from error
    except ValueError as error:
        raise ValueError(f"template has a stray '$': {error}") from error


def render_html_report(review: dict[str, Any], template_text: str, generated_at: str) -> str:
    """Return the HTML page with the review injected into the template."""
    return substitute_template(template_text, build_template_values(review, generated_at))


def find_repository_root() -> Path:
    """Return the root of the checkout the command runs in."""
    return Path(run_command(["git", "rev-parse", "--show-toplevel"]).strip())


def resolve_directories(args: argparse.Namespace) -> tuple[Path, Path]:
    """Return (root, output_dir), each defaulting to the repository root on its own.

    git is consulted only when a default is needed, so a run that names both
    directories works outside any checkout.
    """
    if args.root and args.output_dir:
        return Path(args.root), Path(args.output_dir)
    repository_root = find_repository_root()
    root = Path(args.root) if args.root else repository_root
    output_dir = Path(args.output_dir) if args.output_dir else repository_root
    return root, output_dir


def write_report_pair(markdown_text: str, html_text: str, output_dir: Path) -> list[Path]:
    """Write the two rendered texts as REVIEW.md and REVIEW.html, and return their paths.

    The caller renders both before calling, so a template error cannot leave a
    fresh REVIEW.md next to a stale REVIEW.html.
    """
    markdown_path = output_dir / MARKDOWN_REPORT_NAME
    html_path = output_dir / HTML_REPORT_NAME
    markdown_path.write_text(markdown_text, encoding="utf-8")
    html_path.write_text(html_text, encoding="utf-8")
    return [markdown_path, html_path]


def write_reports(
    review: dict[str, Any], output_dir: Path, template_text: str, generated_at: str
) -> list[Path]:
    """Write REVIEW.md and REVIEW.html into output_dir and return their paths."""
    return write_report_pair(
        render_markdown_report(review),
        render_html_report(review, template_text, generated_at),
        output_dir,
    )


def format_count(count: int, singular: str, plural: str) -> str:
    """Return "1 finding" or "3 findings" style text."""
    return f"{count} {singular if count == 1 else plural}"


def format_summary(review: dict[str, Any]) -> str:
    """Return "N findings in M categories" for the review."""
    return (
        f"{format_count(count_findings(review), 'finding', 'findings')} in "
        f"{format_count(len(list_nonempty_categories(review)), 'category', 'categories')}"
    )


def report_findings_without_code(review: dict[str, Any]) -> None:
    """Print a note naming the findings that show no code, if any."""
    finding_ids = list_findings_without_code(review)
    if not finding_ids:
        return
    print(
        f"note: {format_count(len(finding_ids), 'finding shows', 'findings show')} "
        f"no code example: {', '.join(finding_ids)}"
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
        root, output_dir = resolve_directories(args)
        problems = check_review(review, root)
        if problems:
            report_problems(Path(args.review), problems)
            return 1
        if args.check:
            print(f"OK: {args.review} passes every check ({format_summary(review)})")
            report_findings_without_code(review)
            return 0
        template_text = read_template(Path(args.template) if args.template else TEMPLATE_PATH)
        written = write_reports(review, output_dir, template_text, generated_at)
    except (ValueError, OSError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    for path in written:
        print(f"wrote {path}")
    print(format_summary(review))
    report_findings_without_code(review)
    return 0


if __name__ == "__main__":
    sys.exit(main())
