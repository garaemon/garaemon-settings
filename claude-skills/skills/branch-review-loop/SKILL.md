---
name: branch-review-loop
description: |
  Iterative code review and fix loop. Runs the branch-review skill via a subagent,
  fixes all reported issues, then re-reviews until no findings remain (up to 5
  iterations). REVIEW.md and REVIEW.html accumulate the findings of every
  iteration, each marked fixed or open, so one page tells the whole story of the loop.
  Use this skill when the user wants a thorough review with automatic fixes, says things
  like "review and fix", "branch-review-loop", "レビューして直して", "レビューループ",
  "コードレビューして修正して", "review loop", or asks to iteratively review and fix code.
allowed-tools: Bash(uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/gather_review_context.py:*), Bash(uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/render_review_loop.py:*)
---

# Code Review Loop Skill

Run the branch-review skill in a subagent, read its findings, fix all reported issues,
and repeat until the review comes back clean -- up to 5 iterations maximum.
Respond in the language of Claude Code's `language` setting, defaulting to
Japanese when it is unset.

## Reports

Every iteration writes its own `review.json`, and `render_review_loop.py`
(in `../branch-review/scripts/`, next to this skill) renders all of them into
one `REVIEW.md` and one `REVIEW.html` at the repository root. The page lists
every finding of every iteration with the iteration that raised it and a
status: fixed, open, fixed but not re-reviewed, or clean for an iteration
without findings. Re-render after every review and after every fix pass, so
the reports always show the current state of the loop.

Keep the per-iteration files apart so a later review does not overwrite an
earlier one:

```text
{scratchpad}/branch-review-loop/iteration-1/review.json
{scratchpad}/branch-review-loop/iteration-2/review.json
...
```

The file keeps the name `review.json` so the PostToolUse hook of the
branch-review skill still checks it when the subagent writes it.

## Workflow

### Setup

1. Identify the current branch and working directory.
2. Start with an empty list of previously fixed items.
3. Create `{scratchpad}/branch-review-loop/` for the per-iteration files.
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

For each iteration N (1 to 5):

#### Step 1: Run branch-review in a subagent

Launch an Agent (general-purpose) with `model` set to the choice from Setup
(`opus`, `fable`, or `sonnet`) on the first iteration. On every later one use
the cheaper of that choice and `opus`: `fable` becomes `opus`, while `opus` and
`sonnet` stay as chosen. The first pass surfaces the deep findings; later
passes mostly confirm fixes. Use this prompt structure, marker line first:

```text
branch-review: delegated reviewer

Run the /branch-review skill on the current branch in {working_directory}.
Run every review step yourself in this agent.
Write review.json to {scratchpad}/branch-review-loop/iteration-{N}/review.json
and render the reports from that file.
After REVIEW.md and REVIEW.html are written, do NOT post comments to GitHub.
Do NOT ask for user confirmation about posting PR comments.
When done, report the path of review.json and the finding count.

Previously fixed items (do NOT re-flag these):
{list of previously fixed items, or "None" if first iteration}
```

#### Step 2: Render the cumulative reports and read the findings

After the subagent completes:

1. Render `REVIEW.md` and `REVIEW.html` from every iteration so far, oldest
   first. The subagent's own reports covered only its iteration; this run
   replaces them:

   ```bash
   uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/render_review_loop.py {scratchpad}/branch-review-loop/iteration-1/review.json ... {scratchpad}/branch-review-loop/iteration-{N}/review.json
   ```

   The script prints one line per iteration. When the line for iteration N
   says `No findings.` (the exact sentence `render_review.py` writes when
   every category is empty), the loop is done -- skip to Completion.
2. Read the findings of this iteration from
   `{scratchpad}/branch-review-loop/iteration-{N}/review.json`, not from
   `REVIEW.md`, which now also holds every earlier iteration.
3. Summarize the findings to the user:
   - Show iteration number (e.g., "Iteration 1/5")
   - List each finding briefly (category + short description)
   - Mention that `REVIEW.html` holds every iteration so far, with each
     finding marked fixed or open, for anyone who wants to follow the loop
     in a browser

#### Step 3: Fix all reported issues

For each finding in this iteration's `review.json`:

1. Read the relevant file(s).
2. Apply the fix (edit code, add comments, add tests, rename, etc.).
3. Add the finding to the "previously fixed items" list.

After all fixes:

1. Run the project's checks (lint, typecheck, tests) to verify nothing is broken.
   Use commands from the project's CLAUDE.md or package.json scripts. If a
   check fails, diagnose and fix it before the next review.
2. Re-render the reports with `--latest-fixed`, so the findings of this
   iteration show as fixed rather than open while the next review runs, and
   stay marked "fixed, not re-reviewed" if no review follows:

   ```bash
   uv run --project ${CLAUDE_SKILL_DIR}/../branch-review ${CLAUDE_SKILL_DIR}/../branch-review/scripts/render_review_loop.py {scratchpad}/branch-review-loop/iteration-1/review.json ... {scratchpad}/branch-review-loop/iteration-{N}/review.json --latest-fixed
   ```

3. Loop back to Step 1 unless N was the last iteration.

### Completion

When the loop ends (either no findings or max iterations reached):

1. Leave `REVIEW.md` and `REVIEW.html` in place. They already hold every
   iteration: the findings each one raised, whether the loop fixed them, and
   a clean final iteration when the review came back empty.
2. Report the final result to the user:
   - Total number of iterations performed, and which model reviewed each one
   - Summary of all fixes applied across all iterations
   - Whether the loop ended because the review was clean or because max iterations
     were reached
   - Where `REVIEW.html` is
3. Do NOT commit or push -- leave that to the user.
