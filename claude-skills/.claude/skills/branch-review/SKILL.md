---
name: branch-review
description: |
  Review code changes on the current branch against the branch they merge into
  (the pull request's base branch when one is open, so stacked PRs review only their
  own changes; the repository default branch otherwise), producing REVIEW.md and
  REVIEW.html (with a summary of every finding at the top) and posting inline
  review comments on specific file lines via GitHub API.
  The review can also be scoped to a narrower commit range: the last N commits, one
  commit, or an explicit range.
  Use this skill whenever the user wants a code review, says things like "review",
  "code review", "/branch-review", "レビューして", "コードレビュー", "PRレビュー",
  "変更をチェックして", or asks to check code quality before merging. Also trigger
  when the user asks to review a specific PR by number, or a specific commit range with
  phrases like "最後のコミットだけレビュー", "直近3コミットをレビュー",
  "review the last commit", "review commits abc123..def456".
allowed-tools: Bash(uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py:*), Bash(uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/render_review.py:*), Bash(uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/list_commentable_lines.py:*), Bash(uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/post_review.py:*)
# Claude Code expands ${CLAUDE_SKILL_DIR} in the markdown body and in
# allowed-tools only, never in hook commands, so the hook locates the skill
# through its install path and does nothing where that path is absent.
hooks:
  PostToolUse:
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "skill_dir=\"$HOME/.claude/skills/branch-review\"; [ -d \"$skill_dir\" ] || exit 0; command -v uv >/dev/null 2>&1 || exit 0; uv run --project \"$skill_dir\" \"$skill_dir/scripts/check_review_hook.py\""
---

# Code Review Skill

Perform a systematic code review of the current branch's changes against the
branch they merge into. This skill is language-agnostic and works with any
programming language.

## Review Philosophy

The standard is code a new team member can open, understand on first reading,
and change with confidence: readable, consistent, documented, and tested. Flag
cleverness rather than praising it; a plain 10-line function beats a dense
3-line one that takes thought to parse.

Do not demand that every edge case is handled or every abstraction is
finalized. A working implementation with specific TODO comments marking known
gaps is fine. Check that:

- The code works for the primary use case
- Known limitations are marked with TODO comments (not silently ignored)
- The TODOs are specific enough to act on later (e.g., `// TODO: handle
  cross-device rename failure` not just `// TODO: fix this`)

Flag missing TODOs (incomplete code without any marker) but do not flag
the presence of TODOs as a problem.

## Scripts

All git and GitHub access goes through these scripts, in `scripts/` next to this
file. Claude Code expands `${CLAUDE_SKILL_DIR}` to that directory in this text
and in the `allowed-tools` rule alike, so pass it through unchanged and the
command runs without a permission prompt.

| Script | Use it for |
| --- | --- |
| `gather_review_context.py` | Resolving the review range, the review language, and printing the diff (Steps 1-1.6) |
| `render_review.py` | Checking `review.json` and rendering it into `REVIEW.md` and `REVIEW.html` (Step 4) |
| `check_review_hook.py` | PostToolUse hook that checks `review.json` as soon as it is written; not run directly |
| `list_commentable_lines.py` | Finding which lines can take an inline comment (Step 5) |
| `post_review.py` | Validating and posting the review (Step 5) |
| `commands.py` | Shared git/`gh` runners; not run directly |

**Do not run `git` or `gh` directly.** Base resolution, GitHub host selection and
comment anchoring are all easy to get subtly wrong -- reviewing against the wrong
base wastes the whole review, talking to the wrong host reports that the pull
request does not exist, and one bad anchor makes GitHub reject every comment at
once. The scripts encode those rules and check them. If a script cannot do what
you need, say so rather than reaching for a raw command.

### Running them

**Always run the scripts with `uv run --project ${CLAUDE_SKILL_DIR}`**, never with a bare
`python3`:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py
```

Without `--project`, `uv` walks up from the current directory and attaches to
the `pyproject.toml` of **the repository being reviewed**, with that project's
Python and dependencies. The working directory still has to be inside the
checkout under review; `--project` changes dependency resolution, not `cwd`.
Every script takes `--help`.

### GitHub Enterprise

The scripts derive the GitHub host from the `origin` remote, so a GitHub
Enterprise checkout needs no setup. `gather_review_context.py` prints the host
it resolved as `github_host:` in its `review range` block; if that line names
the wrong server, stop and tell the user rather than posting anything.

## Workflow

### Step 0: Choose the review model

The review runs in a subagent so the user can pick the model for it each time.
Review quality tracks how deeply the model reads, and Claude Fable 5.1 costs
twice Claude Opus 5 per token, so the choice belongs to the user, per diff.

**Skip this step entirely, and never launch a subagent, when either holds:**

- You are yourself a subagent, launched with the Agent tool. A subagent cannot
  ask the user anything, so delegating again would only nest another subagent.
- The prompt that invoked you contains the marker line
  `branch-review: delegated reviewer`, which the parent (this skill or
  branch-review-loop) puts first in the prompt.

In either case start at Step 1 and run every step yourself, except Step 5,
which the parent handles.

Otherwise:

1. Run `gather_review_context.py` first (with the scope flags from Step 1) so
   the question can quote the diff size. Fix the scope flags here; the subagent
   receives them verbatim.
2. Ask one question with AskUserQuestion, quoting the `size` block
   ("N files, +X / -Y"). Offer these options, with these descriptions:
   - **Opus 5**: everyday reviews; the baseline price.
   - **Fable 5.1**: large diffs, or diffs that touch concurrency, security
     boundaries, or shell execution; twice the price of Opus.
   - **Sonnet 5**: small, mechanical diffs; 0.4 times the price of Opus.
   Mark Opus 5 as recommended, except when additions exceed 200 or the changed
   files include authentication, input boundaries, or shell execution, where
   Fable 5.1 is the recommendation.
3. Launch an Agent (general-purpose) with `model` set to the choice (`opus`,
   `fable`, or `sonnet`) and this prompt, marker line first:

   ```text
   branch-review: delegated reviewer

   Run the /branch-review skill in {working_directory} with the scope flags:
   {flags, or "(none: whole branch)"}. Run every review step yourself in
   this agent. Do NOT post comments to GitHub and do NOT ask about posting.
   When done, report the path of review.json and the finding count.
   ```

4. When the subagent finishes, read `REVIEW.md`, summarize the findings to the
   user, tell them where `REVIEW.html` is, and continue with Step 5 yourself.
   Build the posting payload from the `review.json` path the subagent reported.

When AskUserQuestion is unavailable or the run is non-interactive, skip the
question and launch the subagent without `model`, which uses the session's
model.

### Step 1: Gather the diff

Run the script, read its `review range` block, and confirm the scope is what
the user asked for before going further. Read every `NOTE` it prints.

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py
```

#### Scoping the review

By default the whole branch is reviewed. **If the user asked for a narrower
scope, pass the matching flag** -- do not review the whole branch and filter the
findings by hand, because the size check, the file list and the commit list
would all still describe the wrong span.

| The user says | Flag |
| --- | --- |
| "直近のcommitだけ", "just the last commit" | `--last 1` |
| "最後の3コミット", "the last 3 commits" | `--last 3` |
| "このコミットだけ", "review commit abc123" | `--commit abc123` |
| "abc123からdef456まで", an explicit range | `--range abc123..def456` |
| "developブランチとの差分" | `--base develop` |
| nothing about scope | (no flag: whole branch) |

An endpoint named as `origin/<branch>` is fetched before it is resolved, so
`--range origin/develop..HEAD` sees the branch as it is on the server. Every
other endpoint is taken from the local checkout as it stands.

#### How the default base is chosen

With no scope flag the script picks the branch these changes will merge into:
the open pull request's base branch, else the repository default branch, else
local `main` / `master`. For a stacked pull request that is the branch below,
not `main`. If the resolved base looks wrong, override it:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py --base some-other-branch
```

Review the files listed under `files to review`. The script lists deleted files
separately -- ignore those entirely.

To see the actual hunks rather than the whole file, add `--patch` for the full
diff or `--patch-for <path>` for one file. Prefer this over reading a file with
the Read tool when you need to tell changed code from pre-existing code.

### Step 1.5: Check PR size

When the script prints the size `NOTE`, flag PR size in Overall Comments and
propose concrete split boundaries based on the actual changes, then still
review in full. Good split criteria:

- **By layer**: config/build changes, backend logic, frontend/UI, tests
- **By feature**: if multiple independent features are bundled, each becomes
  its own PR
- **By dependency order**: foundational changes (types, shared utilities) first,
  then code that depends on them

### Step 1.6: Note the review language

Write the review text in `review.json` (Step 4) in the language the
`review language` block reports. When it says `(unset)`, use the language the
user is writing in, defaulting to Japanese.

### Step 2: Read all changed files

Read every added or modified file in full before making any judgments. Do not
start writing findings until you have read all changed files. This prevents
shallow or contradictory feedback.

### Step 3: Review by category

Review the code in this order. Focus on the diff, not pre-existing code the
branch did not change. Be specific: give a file path, a line number and a code
snippet for every finding.

#### Show the code

Write every finding around code, not around prose about code. A finding that
the author can act on without opening the file has two fenced blocks:

1. The lines as they are, quoted from the diff, so the reader sees what the
   finding is about without scrolling to the file.
2. The lines as they should be, whenever a concrete fix exists: the renamed
   identifier, the added guard, the missing doc comment, the assertion the
   test lacks. Write the replacement in full rather than describing it.

Tag every fence with the language (`ts`, `python`, `elisp`, and so on), because
`REVIEW.html` colors code through highlight.js and an untagged fence falls back
to a guess. Skip the second block only when no single fix follows from the
finding, such as a missing test file or a design question, and say what the
fix would involve instead. `render_review.py` prints a note naming the
findings that show no code at all; treat each as a prompt to add the snippet,
not as an error.

#### Category 1: Architecture / Config

- Dependency placement and management
- Unnecessary config options
- CI jobs that silently pass (`continue-on-error` on checks that matter)
- Build config inconsistencies
- Mismatched language/tool versions

#### Category 2: Security

- Path traversal (user-controlled paths used in file reads)
- Command injection (unsanitized input in shell commands)
- Missing input validation at trust boundaries (IPC, API endpoints, RPC)
- Credential exposure (secrets in code, credentials committed)
- Injection vulnerabilities (SQL, XSS, etc.)
- Buffer overflows, use-after-free (for C/C++)

This is the most important category. A single security issue can outweigh
dozens of style findings.

#### Category 3: Naming

Names are the primary tool for making code readable. Apply these rules strictly,
regardless of the programming language:

- **Functions must start with verbs.** `getData()` not `data()`, `createWindow()` not `window()`.
- **Names must include role/context.** Prefer specific names that describe the thing's
  role, not just its type. `submitButton` over `button`, `retryCount` over `count`,
  `userEmailInput` over `input`, `saveDebounceTimer` over `timer`.
- **No abbreviations.** `button` not `btn`, `manager` not `mgr`, `configuration` not `cfg`,
  `element` not `el`, `parameters` not `params`. Exception: universally understood
  abbreviations like `url`, `id`, `html`, `css`, `api`.
- **Booleans use `is`/`has`/`should`/`can` prefix.** `isVisible` not `visible`,
  `hasPermission` not `permission`.
- **Flag generic names.** Names like `data`, `info`, `item`, `value`, `result`, `temp`,
  `tmp`, `obj` without qualifying context are too vague. `userData` is fine, bare `data` is not.

Follow the language's naming conventions for casing (camelCase for JS/TS/Java,
snake_case for Python/Rust/C, PascalCase for Go exported names, etc.), but
the rules above about role/context and verbosity apply universally. When
flagging a naming issue, always suggest a concrete better name.

#### Category 4: Documentation / Comments

The target audience for comments is a university senior (4th-year CS student)
who is unfamiliar with the specific framework being used. They are smart and
can read code, but they do not know framework internals or domain-specific patterns.

Use the language's standard doc comment format (e.g., `/** */` for JS/TS/Java,
`///` or `/** */` for C/C++/Rust, `"""docstring"""` for Python, `//` for Go).
Do not prescribe a specific format -- follow whatever is idiomatic for the language.

Check for:

- **Module-level doc comments**: Every file should have a brief comment at the top
  explaining why this module exists, what it does, and (if non-obvious) how it works.
  A reader opening this file for the first time should immediately understand its
  purpose without reading every function.
- **Exported/public function, class, and type doc comments**: All public APIs must
  have doc comments. At minimum: one-sentence description. For complex functions:
  parameter descriptions, return value semantics, side effects, and error conditions.
- **"Why" comments**: Non-obvious logic needs a "why" comment explaining the reasoning.
  Examples: workarounds for library bugs, implicit assumptions, performance trade-offs,
  loop prevention patterns, spec-defined behavior. If you find yourself needing to
  think hard about why code does something, it needs a comment.
- **Do NOT flag missing comments on self-explanatory code.** A function named
  `getBasename` with a clear one-liner body does not need a comment explaining what
  it does. Focus on code where the "why" is not obvious from reading the code.
- **Spec references**: When code implements behavior defined by an external spec
  (e.g., protocol definitions, RFC, language specs), the comment should reference
  the spec section or link.

When flagging a missing comment, briefly describe what the comment should say.

#### Category 5: Logic / Correctness

- Dead code (unreachable branches, unused variables, handlers that do nothing)
- Race conditions (TOCTOU, shared mutable state, lock ordering)
- Error handling gaps (unhandled exceptions, empty catch blocks, ignored return codes)
- Off-by-one errors
- Null/undefined/nullptr access without guards
- State synchronization issues (in-memory state drifting from persisted state)
- Resource leaks (unclosed file handles, missing destructors, leaked memory)

#### Category 6: Tests

- Missing assertions (test sets up state but never asserts)
- Assertions inside conditional blocks (test silently passes if condition is false)
- Test isolation (shared state between tests, tests depending on execution order)
- Misleading test names (test name says one thing, test body checks another)
- Missing test coverage for critical paths
- Flaky patterns (timing-dependent assertions, uncontrolled randomness)

#### Category 7: Style / Consistency

Consistency matters more than any particular style choice. If the codebase uses
one pattern, new code should follow it -- even if another pattern is arguably better.

- Duplicate definitions (same constant in two places, same style in CSS and JS)
- Inconsistent patterns within the same codebase
- Reimplemented stdlib/library functionality (hand-rolled path parsing, mime type
  guessing when a well-maintained library exists)

Skip formatting issues (whitespace, semicolons, quotes, brace placement) if a
formatter is configured in the project.

#### Category 8: Performance

- Blocking calls in async contexts
- Unnecessary full-data copies in hot paths
- Double debouncing / double buffering
- Unnecessary allocations in tight loops
- Missing caching for expensive repeated computations

### Step 4: Write review.json and render the reports

Write the findings to `review.json` in the scratchpad directory, then let the
script render `REVIEW.md` and `REVIEW.html` at the project root from it:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/render_review.py /path/to/scratchpad/review.json
```

The file shape, with the review text in the language resolved in Step 1.6:

```json
{
  "title": "Code Review: add color picker",
  "branch": "feature/color-picker",
  "range": "whole branch against main (repository default branch)",
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
          "body": "The `UPDATE_COLOR` handler accepts arbitrary strings:\n\n```ts\nipcMain.on(UPDATE_COLOR, (_, color) => setColor(color));\n```\n\nValidate the value before it reaches `setColor`:\n\n```ts\nconst HEX_COLOR_PATTERN = /^#[0-9A-Fa-f]{6}$/;\n\nipcMain.on(UPDATE_COLOR, (_, color) => {\n  if (typeof color !== \"string\" || !HEX_COLOR_PATTERN.test(color)) {\n    return;\n  }\n  setColor(color);\n});\n```"
        }
      ]
    }
  ]
}
```

Rules for building the file:

- Copy `branch`, `range` and `pull_request` from the `review range` block and
  `stats` from the `size` block that `gather_review_context.py` printed. Leave
  `pull_request` out when the block says `(none for this branch)`.
- Set `language` to the BCP 47 tag of the review text (`ja` for Japanese, `en`
  for English) so the HTML page declares the language its fonts and screen
  readers should use. Leave it out when unsure.
- `overall_comments` holds cross-cutting concerns that affect the whole
  codebase, such as "documentation is consistently missing" or "naming
  conventions are not followed", plus the PR size note from Step 1.5. Those go
  here, not as individual findings.
- List the categories in the order of Step 3, numbered 1-8. Empty categories
  may be listed or left out; the reports omit them either way.
- Number findings `<category>-<index>` (`2-1`, `2-2`, ...). Ids must be unique.
- `path` is relative to the repository root and `line` is the line on the HEAD
  side. Leave both out for a finding that maps to no single line.
- `body` and `overall_comments` are markdown. The renderer understands
  paragraphs, fenced code blocks, inline code, `**bold**`, bullet and numbered
  lists, and `>` quotes; anything else shows up as plain text. Start every
  fence at column 0, because an indented fence does not open a code block.
  Keep lists flat: a nested item renders as a sibling in the HTML report
  while `REVIEW.md` keeps the nesting.
- Give every finding the current code and the proposed code as fenced blocks
  tagged with the language, as [Show the code](#show-the-code) describes.
- Do not assign priority levels. Every finding in the review should be worth
  the author's attention. If something is too trivial to act on, leave it out
  entirely instead of marking it "Low".

#### Checking the file

The script checks `review.json` before it writes anything and refuses to
render while a problem remains; every failure names the finding and what to
change. A PostToolUse hook declared in this file's frontmatter runs the same
checks the moment `review.json` is written or edited, so problems can also
arrive as tool feedback. To run the checks by hand without writing the
reports:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/render_review.py /path/to/scratchpad/review.json --check
```

Fix `review.json` and run the render command again; do not edit `REVIEW.md`
or `REVIEW.html` by hand, because the next run overwrites both.

When reporting back, say which range you reviewed and tell the user where
`REVIEW.html` is so they can open it in a browser. Both reports stay at the
repository root as untracked files; when the repository's `.gitignore` does
not list `/REVIEW.md` and `/REVIEW.html`, suggest adding them.

### Step 5: PR integration

The parent that asked for the model runs this step, because only the parent
can talk to the user. A delegated reviewer stops after Step 4 and reports the
`review.json` path.

`gather_review_context.py` already reported whether a pull request exists, in the
`pull_request` field of its `review range` block. If one exists, ask the user
in the review language:

> REVIEW.md と REVIEW.html を作成しました。このブランチにPR (#N) があります。PRにインラインレビューコメントを投稿しますか?

If the user confirms, post the review as **inline comments on specific file lines**
using the GitHub Pull Request Review API. Do NOT post without confirmation.

#### How to post inline review comments

Write the findings to a JSON file, then let the script validate and post it.
Write the file to the scratchpad directory, not the user's project.

```json
{
  "body": "Overall summary: cross-cutting concerns, PR size notes, findings that anchor to no single line.",
  "comments": [
    {
      "path": "src/main/index.ts",
      "line": 29,
      "body": "### 2-1. IPC color inputs not validated\n\nThe `UPDATE_COLOR` handler accepts arbitrary strings...\n\nSuggestion: validate against `/^#[0-9A-Fa-f]{6}$/`."
    }
  ]
}
```

Validate first, then post once it is clean:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/post_review.py findings.json --dry-run
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/post_review.py findings.json
```

`post_review.py` fills in `side` and `event`, checks every anchor against the
pull request diff, and refuses to post if any is bad, naming the offending
anchor and the nearest usable line, because GitHub rejects the whole review on
one bad anchor.

To pick anchors while you are still writing findings, ask which lines are
available:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/list_commentable_lines.py
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/list_commentable_lines.py --path src/main/index.ts
```

Anchorable lines come from the pull request's own diff, whatever range you
reviewed: a `--range`, `--commit` or `--base` span that reaches outside the
pull request, or a line a later commit changed back, has nowhere to anchor.
Move such findings to the top-level `body`, together with cross-cutting
concerns such as PR size.

Rules for building the findings file:

- **`line`**: a line on the HEAD side of the diff; added and context lines
  inside a hunk are both anchorable. If a finding refers to a line outside the
  diff, move it to the nearest changed line in the same file, or to `body`.
- **`body`**: use the heading format `### N-N. Short description`, followed by
  the explanation copied from the finding's `body` in `review.json`. Keep each
  comment self-contained -- reviewers may read them individually, so repeat
  the context a reader needs rather than referring to "the finding above".
- **`event`**: leave it out. Only set `"APPROVE"` or `"REQUEST_CHANGES"` when
  the user explicitly asks for one.
