---
name: code-review-loop
description: |
  Iterative code review and fix loop. Runs the code-review skill via a subagent,
  fixes all reported issues, then re-reviews until no findings remain (up to 5 iterations).
  Use this skill when the user wants a thorough review with automatic fixes, says things
  like "review and fix", "code-review-loop", "レビューして直して", "レビューループ",
  "コードレビューして修正して", "review loop", or asks to iteratively review and fix code.
---

# Code Review Loop Skill

Run the code-review skill in a subagent, read its findings, fix all reported issues,
and repeat until the review comes back clean -- up to 5 iterations maximum.

## Workflow

### Setup

1. Identify the current branch and working directory.
2. Initialize an empty list of previously fixed items.
3. Set iteration counter to 0, max iterations to 5.

### Loop

For each iteration:

#### Step 1: Run code-review in a subagent

Launch an Agent (general-purpose) with the following prompt structure:

```text
Run the /code-review skill on the current branch in {working_directory}.

After REVIEW.md is written, do NOT post comments to GitHub.
Do NOT ask for user confirmation about posting PR comments.

Previously fixed items (do NOT re-flag these):
{list of previously fixed items, or "None" if first iteration}
```

The subagent will invoke the code-review skill via the Skill tool, which produces
REVIEW.md at the project root.

#### Step 2: Read and analyze REVIEW.md

After the subagent completes:

1. Read `REVIEW.md` from the project root.
2. Parse the findings. If the review says "No issues found" or has no actionable
   findings, the loop is done -- skip to Completion.
3. Summarize the findings to the user:
   - Show iteration number (e.g., "Iteration 1/5")
   - List each finding briefly (category + short description)

#### Step 3: Fix all reported issues

For each finding in REVIEW.md:

1. Read the relevant file(s).
2. Apply the fix (edit code, add comments, add tests, rename, etc.).
3. Add the finding to the "previously fixed items" list.

After all fixes:

1. Run the project's checks (lint, typecheck, tests) to verify nothing is broken.
   Use commands from the project's CLAUDE.md or package.json scripts.
2. Delete REVIEW.md to prepare for the next iteration.
3. Increment the iteration counter and loop back to Step 1.

### Completion

When the loop ends (either no findings or max iterations reached):

1. Delete REVIEW.md if it exists.
2. Report the final result to the user:
   - Total number of iterations performed
   - Summary of all fixes applied across all iterations
   - Whether the loop ended because the review was clean or because max iterations
     were reached
3. Do NOT commit or push -- leave that to the user.

## Important Rules

- Always respond in Japanese.
- The subagent runs code-review; the parent (this skill) does the fixes.
- Always pass the full list of previously fixed items to each subagent to prevent
  duplicate findings.
- Run lint/typecheck/tests after each round of fixes before the next review.
- If checks fail after fixes, diagnose and fix the failure before proceeding.
- Do not commit changes during the loop. The user decides when to commit.
