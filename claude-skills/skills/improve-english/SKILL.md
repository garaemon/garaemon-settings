---
name: improve-english
description: |
  Improve English quality in code that will be part of a PR: fix spelling in
  variable/function names, improve grammar and naturalness of comments, and
  translate Japanese comments into English. Scoped to changes between
  origin/main and the current branch (committed, staged, and unstaged).
  Use this skill when the user says things like "improve english", "英語直して",
  "英語改善して", "fix english", "clean up english before PR", "英語チェックして",
  "proofread my changes", "日本語コメント直して", or "translate comments".
  Also trigger when the user asks to polish, proofread, or review English
  in their code changes, or to translate Japanese in source code.
---

# Improve English

Improve English quality in code changes that will be part of a PR.
This skill fixes spelling errors in identifiers, improves the grammar
and naturalness of comments, and translates Japanese comments into
English — all without changing code logic or comment meaning.

## Scope

Only touch lines that appear in the diff between `origin/main` and the
current working state. Existing code outside the diff is never modified.

The diff has three layers:

1. **Committed changes** on the current branch (vs `origin/main`)
2. **Staged changes** (indexed but not yet committed)
3. **Unstaged changes** (modified but not staged)

All three layers are in scope. Unchanged lines in `origin/main` are not.

## Workflow

### Step 1: Fetch and collect the diff

```bash
git fetch origin
```

Then gather the full scope of changes:

```bash
# Committed changes on the branch
git diff origin/main...HEAD

# Staged but uncommitted
git diff --cached

# Unstaged modifications
git diff
```

Parse these diffs to build a map of which files and line ranges contain
changes. Only these lines are candidates for improvement.

### Step 2: Read changed files

For each file with changes, read the file and identify:

- **Identifiers** (variable names, function names, class names, etc.)
  that were added or modified in the diff
- **Comments** (inline, block, and doc comments) that were added or
  modified in the diff

### Step 3: Fix identifiers

For identifiers, fix **spelling errors only**. Do not rename for style
or clarity — just correct misspelled English words within the name.

**Example:**

- `getUserInfomation` -> `getUserInformation` (typo fix)
- `calcurate` -> `calculate` (typo fix)
- `recieve_data` -> `receive_data` (typo fix)

Do NOT change:

- Naming conventions (camelCase vs snake_case)
- Abbreviations that are intentional (`cfg`, `ctx`, `req`)
- Domain-specific terms or project conventions

When renaming an identifier, update all references within the same file
to keep the code consistent. If the identifier is exported or used across
files in the diff, update those references too.

### Step 4: Improve comments

For comments in the diff, improve:

- **Japanese comments**: Translate into natural English that preserves the
  original meaning (`// データをサーバから取得する` ->
  `// Fetch data from the server`)
- **Spelling errors**: Fix typos
- **Grammar**: Fix grammatical mistakes (`This function get data` ->
  `This function gets data`)
- **Naturalness**: Rephrase awkward English into clear, idiomatic English
  (`Do getting of data from server` -> `Fetch data from the server`)

Do NOT change:

- The meaning or intent of the comment
- Technical terms, acronyms, or domain jargon
- Comments that are already clear and natural
- TODO markers or their content (but translate Japanese in TODO text)
- Comments outside the diff scope

### Step 5: Apply changes

Apply all fixes directly to the files using the Edit tool. Do not commit
the changes — leave them as unstaged modifications so the user can review
with `git diff`.

### Step 6: Report

After applying all fixes, present a summary:

- Number of files modified
- For each file, list what was changed (briefly)
- If no improvements were needed, say so

## Integration with create-pr

When invoked as part of the create-pr workflow, ask the user for
confirmation before applying changes:

> English improvements are available for N files. Apply them? (y/n)

Show the proposed changes before asking. Only apply after the user
confirms.

## Important rules

- Never modify code logic — only identifiers and comments
- Never touch lines outside the diff scope
- Never commit changes — leave them unstaged for review
- Respect the existing code style (indentation, comment format)
- When unsure if something is a typo vs intentional abbreviation, leave
  it unchanged
