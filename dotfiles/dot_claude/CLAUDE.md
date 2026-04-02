# Instructions

## Coding Style

### Function Length

Keep functions shorter than 90 lines.

### Naming

- Always start functions and methods with verbs.
- Always use descriptive names for variables.

### Inheritance

Avoid class inheritance. Do not use inheritance to reduce duplicated code.

Exceptions:

- Libraries require inheritance.
- You need inheritance of types.

### Formatting

Do not add trailing spaces.

## Comments

### Principle

Prefer self-documenting code over comments. Use descriptive variable and function names to eliminate the need for "what" comments. Comments should focus on "why", not "what".

- BAD: `int n = 3; // number of retries`
- GOOD: `int maxRetryCount = 3;`
- BAD: `// Loop through users` or `// Initialize the counter`
- GOOD: `// Retry up to 3 times because the upstream API is flaky under load.`

### When to Comment

Add comments for: non-obvious business logic, workarounds, implicit assumptions, and performance trade-offs.
Do not add comments to self-explanatory code. Clear naming and types are preferred over comments.

### Doc Comments

Document all exported/public functions and types with doc comments (e.g., JSDoc, GoDoc, docstring).

### Format

Standalone comments must be full sentences. Inline comments (end of line) should be short fragments.

## Development Workflow

### Approach

Implement top-down: start with the overall structure and high-level functions first, even if the internals are empty stubs. Fill in the details afterward. Do not start from low-level details.

### Incremental Development

Don't implement many things at once. Always compile programs or run test codes after you modify the code.

### Branching

Make a branch first before you modify the code if you are on the default branch.

### PR

Before you make a PR, always run tests including linters. Ignore test programs in linter.

## Git

### Branch Naming

Add YYYY.MM.DD- prefix to the branch name.

### Staging

Do not use `git add .`. Specify files to add to git explicitly always.

### Commit and PR Language

Use English for commit messages and pull request descriptions.

## Response Language

Answer in Japanese even if the user uses English. Use Japanese even for writing todo items.

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
