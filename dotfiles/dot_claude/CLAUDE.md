# Instructions

## Coding Style

### Function Length

Keep functions shorter than 90 lines.

### Naming

- Always start functions and methods with verbs.
- Always use descriptive names for variables.

### Immutability

- Do not reassign variables unless there is a specific reason. Prefer introducing new variables.
- Always use `const`-like qualifiers when available (`const` in JS/TS/C++, `final` in Java/Dart, `let` in Swift/Rust, `val` in Kotlin, etc.).

### Inheritance

Avoid class inheritance. Do not use inheritance to reduce duplicated code. Prefer composition (ownership) over inheritance for code reuse.

Exceptions:

- Libraries require inheritance.
- You need inheritance of types.

### Formatting

Do not add trailing spaces.

## Shell Scripts

When creating a new shell script (`*.sh` or `*.bash`), read `~/.claude/rules/shell-script.md` first and follow it.

## Comments

### Principle

Prefer self-documenting code over comments. Use descriptive variable and function names to eliminate the need for "what" comments. Comments should focus on "why", not "what".

- BAD: `int n = 3; // number of retries`
- GOOD: `int maxRetryCount = 3;`
- BAD: `// Loop through users` or `// Initialize the counter`
- GOOD: `// Retry up to 3 times because the upstream API is flaky under load.`

Every comment must add precision or intuition:

- Precision: a detail the code cannot express, such as units, valid ranges, invariants, or lifetimes.
- Intuition: the reason, the trade-off, or a higher-level model of the code.

A comment that adds neither is noise. Delete it.

### Order

Lead with whatever the reader cannot recover from the code.

- When the code states its own effect, write only the reason.
- When the call hides its effect, such as a registration, a property assignment, or a framework hook, state the effect in one sentence, then the reason. That sentence translates the call instead of repeating it, so it is not the redundant "what" that [Principle](#principle) rejects.
- Never make the reader hold a reason in mind before knowing what it justifies.
- BAD: `// The prompt on every visit is tedious.` above a call whose effect the reader cannot see.
- GOOD: `// Accept a list of strings from .dir-locals.el without confirmation. Emacs otherwise prompts on every visit.`

### Volume

Comments spend the reader's attention. Spend it on the few places that need it.

- Write at most one comment per 10 lines of ordinary code.
- Never attach a comment to every line, every block, or every field.
- Keep a standalone comment to 3 lines or fewer. Put longer explanations in the doc comment or a design doc.
- If a function needs many comments to follow, split the function or rename its variables instead.

### When to Comment

Add comments for: non-obvious business logic, workarounds, implicit assumptions, and performance trade-offs.
Do not add comments to self-explanatory code. Clear naming and types are preferred over comments.

Always comment these cases:

- Bug fixes and workarounds. State the bug, and link the issue.
- Unidiomatic code. Explain it so that nobody "fixes" it back.
- Copied code. Link the original source.
- Incomplete work. Write `TODO(<owner>): <what is missing>`, and link the issue.

### Never Write These Comments

- Comments that restate the code or repeat the identifier names.
- Changelog comments, such as `// Now uses the new API` or `// Added error handling`. Git records history.
- Comments about the task or the conversation, such as `// As requested` or `// Per review feedback`.
- Banner or divider comments, such as `// ===== Helpers =====`.
- Commented-out code. Delete it. Git remembers it.
- Vague claims, such as `// for performance` or `// handle edge cases`. Name the actual case.
- Digressions. Cut any fact that does not change how the reader reads or edits this code, however interesting the fact is. Background about the tool, the history, or the alternatives you rejected belongs in a design doc, unless a reader is likely to try one of those alternatives here.

### Wording

- Use different words from the name of the entity you describe. Repeating the name adds nothing.
- Name the subject of every sentence. A pronoun such as "it" or "this" that points back at the previous sentence reads as ambiguous the moment a comment covers two subjects.
- Name the specific system, failure, or constraint. Prefer `// S3 returns 404 for a few seconds after a PUT.` over `// Handle eventual consistency.`
- Standalone comments must be full sentences. Inline comments (end of line) should be short fragments.
- When a comment contains multiple related sentences, prefer a list over a run-on paragraph. See [Technical Writing](#technical-writing).

### Format

- Put a standalone comment on its own line above the code, indented to the same level as that code.
- Put one space after the comment marker.
- Wrap comment lines at the file's line-length limit, or at 80 columns when the project sets none. A URL may exceed the limit.

### Doc Comments

Document all exported/public functions and types with doc comments (e.g., JSDoc, GoDoc, docstring).

- Start with one sentence that tells the caller what the function returns or does.
- Document what the signature cannot say: units, error conditions, side effects, ownership, and valid ranges.
- Skip parameter lines that only repeat the parameter name.

### Maintenance

- Update or delete nearby comments whenever you change the code they describe. A stale comment misleads the reader worse than no comment.
- If you cannot write a clear comment, the code is probably unclear. Fix the code first.

## Technical Writing

Follow Google's [Technical Writing](https://developers.google.com/tech-writing) style in all prose: README, design docs, PR descriptions, commit messages, doc comments, and code comments. Always apply these core rules:

- Express one idea per sentence, and keep sentences short.
- Prefer active voice and strong verbs over passive voice.
- Replace a run-on paragraph of related items with a bulleted or numbered list.
- Introduce each list with a sentence that ends in a colon, and keep items parallel.

For the full checklist (word choice, pronouns, paragraphs, lists and tables, audience), load the `technical-writing` skill.

## Development Workflow

### Approach

Implement top-down: start with the overall structure and high-level functions first, even if the internals are empty stubs. Fill in the details afterward. Do not start from low-level details.

### Incremental Development

Don't implement many things at once. Always compile programs or run test codes after you modify the code.

### Branching

Make a branch first before you modify the code if you are on the default branch.

### Bug Reproduction

When the user reports an error or bug, first try to reproduce it with automated code (a script or a failing test) before attempting a fix. Once reproduced, add the reproduction as a test eventually, so the bug stays covered by the test suite.

### PR

Before you make a PR, always run tests including linters. Ignore test programs in linter.

## Git

### Branch Naming

Add YYYY.MM.DD- prefix to the branch name.

### Staging

Do not use `git add .`. Specify files to add to git explicitly always.

### Commit Granularity

- Think about commit units at the hunk level, not the file level.
- When one file contains changes for different purposes, split them into separate commits with `git add -p` (or `git apply --cached` with a partial patch).
- Group hunks by purpose: one logical change per commit (e.g., a refactor and a feature change must not share a commit even if they touch the same file).

### Commit and PR Language

Use English for commit messages and pull request descriptions.

## Response Language

Answer in Japanese even if the user uses English. Use Japanese for the following too:

- Todo items.
- Implementation plans, including plan mode output.

## File Content

Do not include Japanese in files.

## Testing Conventions

### TDD Workflow

- Always write failing tests BEFORE implementation
- Use AAA pattern: Arrange-Act-Assert
- One assertion per test when possible
- Test names describe behavior: "should_return_empty_when_no_items"

### Test-First Rules

- When I ask for a feature, write tests first
- Tests should FAIL initially (no implementation exists)
- Only after tests are written, implement minimal code to pass
