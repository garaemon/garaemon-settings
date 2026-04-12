---
name: code-review
description: |
  Review code changes on the current branch against the default branch (auto-detected;
  supports main, master, etc.), producing a structured REVIEW.md and posting inline
  review comments on specific file lines via GitHub API.
  Use this skill whenever the user wants a code review, says things like "review",
  "code review", "/code-review", "レビューして", "コードレビュー", "PRレビュー",
  "変更をチェックして", or asks to check code quality before merging. Also trigger
  when the user asks to review a specific PR by number.
---

# Code Review Skill

Perform a systematic code review of the current branch's changes against main.
This skill is language-agnostic and works with any programming language.

## Review Philosophy

Good code is **readable, consistent, documented, and tested**. That is the
standard. Not clever code, not elegant code, not code that shows off a neat
trick. Code that a new team member can open, understand quickly, and modify
with confidence.

When reviewing, ask: "Would a competent developer unfamiliar with this
codebase understand this code on first reading?" If the answer is no, that
is a finding -- whether the fix is a better name, a doc comment, a simpler
structure, or all three.

Do not praise cleverness. Flag it. Clever code is a maintenance burden.
A straightforward 10-line function is better than a dense 3-line function
that requires careful thought to parse. Readable code does not need to be
verbose -- it needs to be clear.

Perfection is not the goal. Start small, ship fast, iterate. A working
implementation with TODO comments marking known gaps is better than a
stalled over-engineered one. When reviewing, do not demand that every edge
case is handled or every abstraction is finalized. Instead, check that:

- The code works for the primary use case
- Known limitations are marked with TODO comments (not silently ignored)
- The TODOs are specific enough to act on later (e.g., `// TODO: handle
  cross-device rename failure` not just `// TODO: fix this`)

Flag missing TODOs (incomplete code without any marker) but do not flag
the presence of TODOs as a problem.

## Workflow

### Step 0: Detect the default branch and fetch

Detect the repository's default branch -- it may be `main`, `master`, or something
else. Use the following command:

```bash
git remote show origin | sed -n 's/  HEAD branch: //p'
```

If this fails (e.g., no remote configured), fall back to checking which of `main` or
`master` exists locally:

```bash
git branch --list main master | head -1 | tr -d ' '
```

Store the result as `DEFAULT_BRANCH` and use it in all subsequent commands instead of
hardcoding `main`.

Then fetch the latest state of the default branch from origin so the diff is up to date:

```bash
git fetch origin $DEFAULT_BRANCH
```

Use `origin/$DEFAULT_BRANCH` (not the local branch) as the base for all diffs and logs
below to ensure comparison against the latest upstream state.

### Step 1: Gather the diff

```bash
git diff --stat origin/$DEFAULT_BRANCH..HEAD
git diff --name-status origin/$DEFAULT_BRANCH..HEAD
git log --oneline origin/$DEFAULT_BRANCH..HEAD
```

Identify all added and modified files. Ignore deleted files entirely.

### Step 1.5: Check PR size

If the diff has more than 200 lines of additions, flag this in Overall Comments
and suggest splitting into smaller PRs. (Use `origin/$DEFAULT_BRANCH` as the base.)

When suggesting a split, propose concrete PR boundaries based on the actual
changes. Good split criteria:

- **By layer**: config/build changes, backend logic, frontend/UI, tests
- **By feature**: if multiple independent features are bundled, each becomes
  its own PR
- **By dependency order**: foundational changes (types, shared utilities) first,
  then code that depends on them

Example suggestion format:
> This PR has 5,000 lines of additions across 40 files. Consider splitting:
>
> 1. **PR1: Infrastructure** -- package.json, tsconfig, CI config (5 files)
> 2. **PR2: Core logic** -- store, file-watcher, window-manager (8 files)
> 3. **PR3: Editor** -- CodeMirror setup, language support (6 files)
> 4. **PR4: UI + tests** -- toolbar, settings, unit/e2e tests (12 files)

Still proceed with the full review even if the PR is large -- the user may
have good reasons for keeping it as one PR. The split suggestion is advisory.

### Step 2: Read all changed files

Read every added or modified file in full before making any judgments. Do not
start writing findings until you have read all changed files. This prevents
shallow or contradictory feedback.

Group files mentally by layer:

- Config / build (package.json, CMakeLists.txt, Makefile, pyproject.toml, etc.)
- Core logic / backend
- Frontend / UI
- Shared types, constants, utilities
- Tests
- Documentation

### Step 3: Review by category

Review the code in this order. Each category has specific things to look for.

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
the rules above about role/context and verbosity apply universally.

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

### Step 4: Write REVIEW.md

Write findings to `REVIEW.md` at the project root.

Structure:

```markdown
# Code Review: [branch description]

Branch: `branch-name`
N files changed, X insertions, Y deletions

## Overall Comments

[Cross-cutting concerns that affect the whole codebase.
Things like "documentation is consistently missing" or
"naming conventions are not followed" go here, not as
individual items.]

---

## 1. Architecture / Config

### 1-1. [filename:line] Short description

Explanation with code snippet.

### 1-2. ...

---

## 2. Security
...

## 3. Naming
...

[Continue through all 8 categories. Omit empty categories.]
```

Do not assign priority levels. Every finding in the review should be
worth the author's attention. If something is too trivial to act on,
leave it out entirely instead of marking it "Low".

### Step 5: PR integration

After writing REVIEW.md, check if a PR exists:

```bash
gh pr view --json number,url 2>/dev/null
```

If a PR exists, ask the user:

> REVIEW.md を作成しました。このブランチにPR (#N) があります。PRにインラインレビューコメントを投稿しますか?

If the user confirms, post the review as **inline comments on specific file lines**
using the GitHub Pull Request Review API. Do NOT post without confirmation.

#### How to post inline review comments

Build a JSON payload and submit it via `gh api`. Each finding becomes an inline
comment attached to the exact file and line it references.

```bash
gh api -X POST repos/{owner}/{repo}/pulls/{number}/reviews \
  --input /dev/stdin <<'JSON'
{
  "body": "Overall summary of the review (cross-cutting concerns, PR size notes, etc.)",
  "event": "COMMENT",
  "comments": [
    {
      "path": "relative/path/to/file.ts",
      "line": 29,
      "side": "RIGHT",
      "body": "### 2-1. IPC color inputs not validated\n\nThe `UPDATE_COLOR` handler accepts arbitrary strings...\n\nSuggestion: validate against `/^#[0-9A-Fa-f]{6}$/`."
    },
    {
      "path": "relative/path/to/other.ts",
      "line": 86,
      "side": "RIGHT",
      "body": "### 5-1. Async callback in 'closed' event\n\n..."
    }
  ]
}
JSON
```

Rules for building the payload:

- **`path`**: relative to the repo root (e.g., `stickies-md-electron/src/main/index.ts`),
  NOT an absolute filesystem path.
- **`line`**: the line number in the file on the HEAD side of the diff (the new version).
  This must be a line that actually appears in the diff. If the finding refers to a line
  that is not part of the diff (unchanged context), attach it to the nearest changed line
  in the same file, or fall back to a general review comment in `body`.
- **`side`**: always `"RIGHT"` (we comment on the new code, not the removed code).
- **`body`**: use the same heading format as REVIEW.md (`### N-N. Short description`),
  followed by explanation. Use markdown. Keep each comment self-contained -- reviewers
  may read them individually.
- **`event`**: use `"COMMENT"` (neutral). Do NOT use `"REQUEST_CHANGES"` or `"APPROVE"`
  unless the user explicitly asks.
- Put cross-cutting concerns (PR size, overall architecture notes) in the top-level
  `"body"` field, not as inline comments.
- If a finding cannot be mapped to a specific diff line (e.g., a missing file, a
  cross-file concern), include it only in the top-level `"body"`.

To find the correct line numbers in the diff, run:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/files --jq '.[].patch' | head -100
```

Or use the line numbers you already collected during Step 2/3 reading. Verify the
line exists in the diff by checking `git diff origin/$DEFAULT_BRANCH..HEAD -- <file>`.

## Important Rules

- Always respond in Japanese.
- Read ALL changed files before writing any findings. No exceptions.
- Do not review deleted files.
- Focus on the diff, not pre-existing code that was not changed in this branch.
- Be specific: include file paths, line numbers, and code snippets for every finding.
- When flagging a naming issue, always suggest a concrete better name.
- When flagging a missing comment, briefly describe what the comment should say.
