"""Tests for the unified-diff parsing shared by the branch-review scripts.

Run with: python3 -m unittest discover -s scripts
"""

import unittest

from list_commentable_lines import collect_commentable_lines, parse_hunk_header


class ParseHunkHeaderTest(unittest.TestCase):
    """parse_hunk_header reads the new-side start line and line count."""

    def test_returns_start_and_count(self) -> None:
        self.assertEqual(parse_hunk_header("@@ -10,2 +11,3 @@ func up() {"), (11, 3))

    def test_treats_omitted_count_as_one(self) -> None:
        self.assertEqual(parse_hunk_header("@@ -30 +32 @@"), (32, 1))

    def test_reads_zero_count_for_pure_deletion(self) -> None:
        self.assertEqual(parse_hunk_header("@@ -7,2 +8,0 @@"), (8, 0))

    def test_returns_none_for_a_non_header(self) -> None:
        self.assertIsNone(parse_hunk_header("+not a header"))


class CollectCommentableLinesTest(unittest.TestCase):
    """collect_commentable_lines returns every new-side line in the patch."""

    def test_collects_added_lines(self) -> None:
        patch = "@@ -0,0 +1,3 @@\n+one\n+two\n+three\n"
        self.assertEqual(collect_commentable_lines(patch), {1, 2, 3})

    def test_counts_context_lines_as_commentable(self) -> None:
        patch = "@@ -1,3 +1,4 @@\n context\n+added\n context\n"
        self.assertEqual(collect_commentable_lines(patch), {1, 2, 3})

    def test_does_not_advance_on_removed_lines(self) -> None:
        patch = "@@ -1,3 +1,1 @@\n-gone\n-gone\n kept\n"
        self.assertEqual(collect_commentable_lines(patch), {1})

    def test_handles_multiple_hunks(self) -> None:
        patch = "@@ -1,0 +1,2 @@\n+a\n+b\n@@ -10,0 +20,1 @@\n+c\n"
        self.assertEqual(collect_commentable_lines(patch), {1, 2, 20})

    def test_ignores_the_no_newline_marker(self) -> None:
        patch = "@@ -1,0 +1,2 @@\n+a\n+b\n\\ No newline at end of file\n"
        self.assertEqual(collect_commentable_lines(patch), {1, 2})

    def test_treats_an_empty_line_as_context(self) -> None:
        # GitHub patches may carry a bare "" where a blank context line sits.
        patch = "@@ -1,3 +1,3 @@\n a\n\n+b\n"
        self.assertEqual(collect_commentable_lines(patch), {1, 2, 3})

    def test_returns_empty_for_an_empty_patch(self) -> None:
        self.assertEqual(collect_commentable_lines(""), set())


if __name__ == "__main__":
    unittest.main()
