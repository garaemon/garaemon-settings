---
name: fix-agent-todo
description: >
  Find and fix all TODO(agent) comments in the codebase. This skill searches for
  TODO(agent) markers across all file types, implements the requested change described
  in each TODO, and removes the TODO comment afterward. Use this skill whenever the user
  mentions fixing TODOs, resolving TODO(agent) items, or says things like "TODO直して",
  "fix todos", "fix agent todo", "TODO(agent)を処理して", "TODOを片付けて".
  Also trigger when the user asks to "clean up TODOs" or "handle remaining TODOs"
  in the context of agent-tagged items. Only TODO(agent) comments are processed —
  all other TODO variants (plain TODO, TODO(username), FIXME, etc.) are left untouched.
---

# Fix Agent TODOs

This skill finds every `TODO(agent)` comment in the project, implements the change
each one describes, and removes the TODO comment once the fix is applied.

## Why this exists

`TODO(agent)` is a convention for marking work that an AI agent should handle —
small, well-scoped tasks like adding validation, renaming a variable, extracting
a helper, or improving error handling. By collecting and resolving them in one pass,
developers can drop breadcrumbs while coding and let the agent clean up later.

## Workflow

1. **Search** — Use Grep to find all occurrences of `TODO(agent)` across the entire project.
   The pattern to search for is `TODO\(agent\)`. Search all file types.

2. **Plan** — Group the results by file. For each TODO(agent), read the surrounding
   context (the function or block it lives in) to understand what change is needed.
   Present a summary to the user before making changes:
   - File path and line number
   - The TODO(agent) text
   - Brief description of what you'll do

3. **Fix** — For each TODO(agent), implement the described change. Keep changes
   minimal and focused — do exactly what the TODO asks, nothing more. After applying
   the fix, remove the TODO(agent) comment line entirely. If the TODO comment is the
   only content on that line, remove the whole line. If it's an inline comment at the
   end of a code line, remove just the comment portion.

4. **Verify** — After all fixes are applied, search again to confirm zero
   `TODO(agent)` comments remain. If the project has a test or build command
   available, run it to make sure nothing is broken.

## Important details

- **Only `TODO(agent)`** — Ignore `TODO`, `TODO(someone)`, `FIXME`, `HACK`,
  `XXX`, and any other annotation. The parenthetical must be exactly `(agent)`.
- **Understand before changing** — Read enough surrounding code to make a correct
  fix. A TODO saying "add error handling" requires understanding what errors can
  occur in that context.
- **One logical commit** — All fixes should be part of a single cohesive set of
  changes, not scattered across multiple unrelated modifications.
- **Respect the codebase style** — Match the existing code style (indentation,
  naming conventions, patterns) when implementing fixes.
- **Don't over-engineer** — If a TODO says "add a nil check", add a nil check.
  Don't refactor the whole function.

## Example

Before:

```go
func GetUser(id string) (*User, error) {
    // TODO(agent): Add input validation for empty id
    user, err := db.FindUser(id)
    if err != nil {
        return nil, err
    }
    return user, nil
}
```

After:

```go
func GetUser(id string) (*User, error) {
    if id == "" {
        return nil, fmt.Errorf("user id must not be empty")
    }
    user, err := db.FindUser(id)
    if err != nil {
        return nil, err
    }
    return user, nil
}
```
