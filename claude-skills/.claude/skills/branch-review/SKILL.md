---
name: branch-review
description: |
  Review code changes on the current branch against the branch they merge into
  (the pull request's base branch when one is open, so stacked PRs review only their
  own changes; the repository default branch otherwise), producing a structured
  REVIEW.md and posting inline review comments on specific file lines via GitHub API.
  Use this skill whenever the user wants a code review, says things like "review",
  "code review", "/branch-review", "レビューして", "コードレビュー", "PRレビュー",
  "変更をチェックして", or asks to check code quality before merging. Also trigger
  when the user asks to review a specific PR by number.
allowed-tools: Bash(uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py:*), Edit(REVIEW.md)
---

# Code Review Skill

Perform a systematic code review of the current branch's changes against the
branch they merge into. This skill is language-agnostic and works with any
programming language.

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

## Scripts

All git and GitHub access goes through these scripts, in `scripts/` next to this
file. Claude Code expands `${CLAUDE_SKILL_DIR}` below to that directory, in this
text and in the `allowed-tools` rule alike, so the command matches the rule and
runs without a permission prompt. Pass it through unchanged rather than
substituting a path of your own.

| Script | Use it for |
| --- | --- |
| `gather_review_context.py` | Resolving the review range, the review language, and printing the diff (Steps 0-1.6) |
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

`--project` is required, not decorative. Without it `uv` searches upward from the
current directory for a `pyproject.toml` and would attach to **the repository
being reviewed**, picking up that project's Python version and dependencies.
Pointing it at the skill directory pins the interpreter to the one in `uv.lock`
regardless of which repository the review runs in. The working directory still
has to be inside the checkout under review -- `--project` changes dependency
resolution, not `cwd`.

The scripts are standard library only, so `uv` resolves them without a network
fetch after the first run.

Every script takes `--help`. Their unit tests run with:

```bash
uv run --project ${CLAUDE_SKILL_DIR} -m unittest discover \
  -s ${CLAUDE_SKILL_DIR}/scripts -t ${CLAUDE_SKILL_DIR}/scripts
```

### GitHub Enterprise

The scripts derive `GH_HOST` from the `origin` remote and pass it to every `gh`
call, so a GitHub Enterprise checkout works with no setup. Both remote URL forms
are understood: `git@github.example.com:owner/repo.git` and
`https://github.example.com/owner/repo.git`.

An inherited `GH_HOST` is deliberately overridden -- the repository under review
decides which server to talk to, not the ambient environment.
`gather_review_context.py` prints the host it resolved as `github_host:` in its
`review range` block; if that line names the wrong server, stop and tell the user
rather than posting anything.

## Workflow

### Step 0-1: Gather the diff

Run the script. It resolves the range, fetches what it needs, and prints the
range, the review language, the diff size, the changed files, the per-file stat,
and the commits in one pass:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py
```

Read its `review range` block and confirm the base is what you expect before
going further. The base is **the branch these changes will actually merge
into**, which is not always the repository default:

| Situation | Base used |
| --- | --- |
| Pull request open for this branch | that PR's base branch |
| No pull request yet | repository default branch |
| Neither resolves | local `main` / `master` |

This matters most for **stacked pull requests**, where the PR targets the branch
below it rather than `main`. Diffing against `main` there pulls in every change
from the PRs underneath and makes you review work that was already reviewed. If
the resolved base looks wrong, override it:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/gather_review_context.py --base some-other-branch
```

Everything is measured from the merge-base, so commits that landed on the base
after this branch was cut are excluded.

Review the files listed under `files to review`. The script lists deleted files
separately -- ignore those entirely.

To see the actual hunks rather than the whole file, add `--patch` for the full
diff or `--patch-for <path>` for one file. Prefer this over reading a file with
the Read tool when you need to tell changed code from pre-existing code.

### Step 1.5: Check PR size

`gather_review_context.py` prints a `NOTE` when additions exceed 200. When it does, flag
PR size in Overall Comments and suggest splitting into smaller PRs.

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

### Step 1.6: Note the review language

The script reports Claude Code's `language` setting:

```text
=== review language ===
language:      japanese
source:        /home/you/.claude/settings.json
```

Write REVIEW.md in that language. When it reports `(unset)`, write in the
language the user is using, defaulting to Japanese.

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

Write findings to `REVIEW.md` at the project root, in the language resolved in
Step 1.6.

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

`gather_review_context.py` already reported whether a pull request exists, in the
`pull_request` field of its `review range` block. If one exists, ask the user
in the review language:

> REVIEW.md を作成しました。このブランチにPR (#N) があります。PRにインラインレビューコメントを投稿しますか?

If the user confirms, post the review as **inline comments on specific file lines**
using the GitHub Pull Request Review API. Do NOT post without confirmation.

#### How to post inline review comments

Write the findings to a JSON file, then let the script validate and post it.
Write the file to the scratchpad directory, not the user's project.

```json
{
  "body": "Overall summary: cross-cutting concerns, PR size notes, findings that anchor to no single line.",
  "event": "COMMENT",
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

The script fills in `"side": "RIGHT"` and defaults `"event"` to `"COMMENT"`, so
neither belongs in the file. It checks every anchor against the pull request
diff before sending anything, and refuses to post if any is bad -- **GitHub
rejects the entire review when a single comment anchors outside the diff**, so
one wrong line number would otherwise lose every finding. On failure it names
the offending anchor and the nearest usable line:

```text
error: refusing to post; GitHub rejects the whole review on a bad anchor
  Makefile:999 - not in the diff; nearest anchorable line is 68
  no/such/file.go:1 - file is not in the pull request diff
```

To pick anchors while you are still writing findings, ask which lines are
available:

```bash
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/list_commentable_lines.py
uv run --project ${CLAUDE_SKILL_DIR} ${CLAUDE_SKILL_DIR}/scripts/list_commentable_lines.py --path src/main/index.ts
```

Rules for building the findings file:

- **`path`**: relative to the repo root, NOT an absolute filesystem path.
- **`line`**: a line on the HEAD side of the diff. Added *and* context lines
  inside a hunk are both anchorable. If a finding refers to a line outside the
  diff, move it to the nearest changed line in the same file, or to `body`.
- **`body`**: use the same heading format as REVIEW.md (`### N-N. Short
  description`), followed by the explanation. Keep each comment self-contained
  -- reviewers may read them individually, so repeat the context a reader needs
  rather than referring to "the finding above".
- **`event`**: leave it out. Only set `"APPROVE"` or `"REQUEST_CHANGES"` when
  the user explicitly asks for one.
- Put cross-cutting concerns (PR size, overall architecture notes) and any
  finding that maps to no single line in the top-level `"body"`.

## Important Rules

- Write REVIEW.md in the language the script reports under `review language`.
- Use the scripts in `scripts/` for all git and GitHub access. Do not run `git`
  or `gh` directly.
- Invoke every script with `uv run --project ${CLAUDE_SKILL_DIR}`, never a bare `python3`.
- Review against the base the branch actually merges into, which for a stacked
  pull request is the PR's base branch, not the repository default.
- Read ALL changed files before writing any findings. No exceptions.
- Do not review deleted files.
- Focus on the diff, not pre-existing code that was not changed in this branch.
- Be specific: include file paths, line numbers, and code snippets for every finding.
- When flagging a naming issue, always suggest a concrete better name.
- When flagging a missing comment, briefly describe what the comment should say.
