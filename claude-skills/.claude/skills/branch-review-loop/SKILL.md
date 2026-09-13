---
name: branch-review-loop
description: |
  Iterative code review and fix loop. Runs the branch-review skill via a subagent
  (which writes REVIEW.md and REVIEW.html), fixes all reported issues, then
  re-reviews until no findings remain (up to 5 iterations).
  Use this skill when the user wants a thorough review with automatic fixes, says things
  like "review and fix", "branch-review-loop", "レビューして直して", "レビューループ",
  "コードレビューして修正して", "review loop", or asks to iteratively review and fix code.
allowed-tools: Bash(uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/gather_review_context.py:*)
---

# Code Review Loop Skill

Run the branch-review skill in a subagent, read its findings, fix all reported issues,
and repeat until the review comes back clean -- up to 5 iterations maximum.

## Workflow

### Setup

1. Identify the current branch and working directory.
2. Initialize an empty list of previously fixed items.
3. Set iteration counter to 0, max iterations to 5.
4. Measure the diff so the question can quote its size and recommend by it:

   ```bash
   uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/gather_review_context.py
   ```

5. Ask which model reviews the first iteration, with AskUserQuestion. Offer
   the options listed under Step 0 of the branch-review skill
   (`../branch-review/SKILL.md`, next to this file) with the descriptions
   given there, and mark the recommended one by the rule given there, so the
   two skills never quote different prices or recommendations. When
   AskUserQuestion is unavailable or the run is non-interactive, skip the
   question and use the session's model.

### Loop

For each iteration:

#### Step 1: Run branch-review in a subagent

Launch an Agent (general-purpose) with `model` set to the choice from Setup
(`opus`, `fable`, or `sonnet`) on the first iteration. On every later one use
the cheaper of that choice and `opus`: `fable` becomes `opus`, while `opus` and
`sonnet` stay as chosen. The first pass surfaces the deep findings, so it gets
the model the user picked; later passes mostly confirm fixes, which never need
a model more expensive than Opus 5. Use this prompt structure, marker line
first:

```text
branch-review: delegated reviewer

Run the /branch-review skill on the current branch in {working_directory}.
Run every review step yourself in this agent.
After REVIEW.md and REVIEW.html are written, do NOT post comments to GitHub.
Do NOT ask for user confirmation about posting PR comments.

Previously fixed items (do NOT re-flag these):
{list of previously fixed items, or "None" if first iteration}
```

The subagent will invoke the branch-review skill via the Skill tool, which produces
REVIEW.md and REVIEW.html at the project root. The marker line tells
branch-review that the model is already chosen, so it neither asks again nor
delegates; keep it as the first line of the prompt.

#### Step 2: Read and analyze REVIEW.md

After the subagent completes:

1. Read `REVIEW.md` from the project root.
2. Parse the findings. If the review says "No findings." (the exact sentence
   `render_review.py` writes when every category is empty) or has no actionable
   findings, the loop is done -- skip to Completion.
3. Summarize the findings to the user:
   - Show iteration number (e.g., "Iteration 1/5")
   - List each finding briefly (category + short description)
   - Mention that `REVIEW.html` holds the full report with a summary table,
     for anyone who wants to read this iteration's findings in a browser

#### Step 3: Fix all reported issues

For each finding in REVIEW.md:

1. Read the relevant file(s).
2. Apply the fix (edit code, add comments, add tests, rename, etc.).
3. Add the finding to the "previously fixed items" list.

After all fixes:

1. Run the project's checks (lint, typecheck, tests) to verify nothing is broken.
   Use commands from the project's CLAUDE.md or package.json scripts.
2. Leave REVIEW.md and REVIEW.html in place. The next review overwrites
   both, and they stay readable until then.
3. Increment the iteration counter and loop back to Step 1.

### Completion

When the loop ends (either no findings or max iterations reached):

1. Leave the last REVIEW.md and REVIEW.html in place, so the user can still
   open the final iteration's report. They are local artifacts of the
   branch-review skill and belong in the repository's `.gitignore`.
2. Report the final result to the user:
   - Total number of iterations performed, and which model reviewed each one
   - Summary of all fixes applied across all iterations
   - Whether the loop ended because the review was clean or because max iterations
     were reached
3. Do NOT commit or push -- leave that to the user.

## Important Rules

- Respond in the language of Claude Code's `language` setting, defaulting to
  Japanese when it is unset.
- The subagent runs branch-review; the parent (this skill) does the fixes.
- The user picks the model for the first review; every later review runs on
  the cheaper of that choice and `opus`. Pass the marker line so the subagent
  never asks.
- Always pass the full list of previously fixed items to each subagent to prevent
  duplicate findings.
- Run lint/typecheck/tests after each round of fixes before the next review.
- If checks fail after fixes, diagnose and fix the failure before proceeding.
- Do not commit changes during the loop. The user decides when to commit.
