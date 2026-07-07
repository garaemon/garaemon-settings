---
name: project-init
description: >
  Scaffold a new project from a language-specific template, wiring up linters,
  formatters, git pre-commit hooks, Claude Code hooks, and a GitHub Actions CI
  workflow so the project is lint-clean and CI-green from the first commit.
  Supports Python (ruff + pyright + pytest, uv), TypeScript/Node (eslint +
  prettier + tsc + vitest), and Go (golangci-lint + gofmt + go test). New
  languages are added by dropping a directory under `templates/`. Use this
  skill when the user starts a new project or repository and wants the tooling
  set up, or says things like "新しいプロジェクト作って", "プロジェクトの雛形",
  "プロジェクト初期化して", "linterとhooks設定して", "scaffold a new project",
  "bootstrap a project", "set up a new repo with linters", "project template",
  "start a new Python/Node/Go project". Ask for the language if it is not clear
  from the request.
---

# Project Init

Scaffold a new project from a curated, per-language template. The result is a
project that already has consistent formatting, linting, type checking, tests,
git pre-commit hooks, a Claude Code SessionStart hook, and a GitHub Actions CI
workflow — all green out of the box.

## Why this exists

Every new project starts with the same yak-shave: pick a linter, a formatter, a
type checker, wire pre-commit, write a CI workflow, add a sensible `.gitignore`.
This skill collapses that into one step and keeps the choices consistent across
projects. The templates are opinionated but standard, so a fresh project passes
its own CI on the very first commit.

## Layout

The skill is parameterized by language. Each supported language is a directory
under `templates/`, plus a shared `common/` directory:

```text
$CLAUDE_PLUGIN_ROOT/skills/project-init/templates/
├── common/     # language-agnostic files: .editorconfig, README skeleton, and
│               # the shared .claude/hooks/format.sh formatter hook
├── python/     # ruff, pyright, pytest, uv, pre-commit, CI, SessionStart hook
├── node/       # eslint, prettier, tsc, vitest, pre-commit, CI, SessionStart hook
└── go/         # golangci-lint, gofmt, go test, pre-commit, CI, SessionStart hook
```

The PostToolUse formatter hook (`.claude/hooks/format.sh`) is a single shared
script under `common/` that dispatches by file extension, so it is maintained
in one place and copied into every project. Each language directory carries
only its own `.claude/settings.json` (whose `SessionStart` command differs).

Adding a language is purely additive: create `templates/<lang>/` with the same
kinds of files and this skill picks it up — no change to the workflow below.

## Inputs to gather

Before scaffolding, establish these. Ask only for what you cannot infer.

1. **Language** — one of `python`, `node`, `go`. If the user did not say and it
   is not obvious from context, ask.
2. **Project name** — defaults to the target directory's basename. Used for
   `__PROJECT_NAME__`.
3. **One-line description** — optional; used for `__PROJECT_DESCRIPTION__`.
   Default to a short placeholder the user can edit later.
4. **Target directory** — where to scaffold. Default to the current working
   directory if it is empty; otherwise ask whether to create a new subdirectory
   named after the project.
5. **Module path (Go only)** — e.g. `github.com/<user>/<project>`. Used for
   `__MODULE_PATH__` in `go.mod`. Default to
   `github.com/<git user or "example">/<project name>` and confirm.

## Workflow

1. **Guard the target.** If the target directory already contains files that the
   template would overwrite (`README.md`, `.gitignore`, `pyproject.toml`,
   `package.json`, `go.mod`, `.github/`, `.claude/`, ...), stop and ask the user
   how to proceed rather than clobbering. Scaffolding into an empty directory or
   a brand-new subdirectory is the happy path.

2. **Copy templates.** Copy the shared files first, then the language files, so
   language files win on any overlap. Copy dotfiles and nested directories too —
   note the trailing `/.`:

   ```bash
   TPL="$CLAUDE_PLUGIN_ROOT/skills/project-init/templates"
   cp -R "$TPL/common/." "$DEST/"
   cp -R "$TPL/<language>/." "$DEST/"
   ```

3. **Substitute placeholders.** Replace across every copied file:
   - `__PROJECT_NAME__` → project name
   - `__PROJECT_DESCRIPTION__` → description (or a short default)
   - `__MODULE_PATH__` → Go module path (Go only)

   Do this in place, e.g. per placeholder:

   ```bash
   grep -rlZ '__PROJECT_NAME__' "$DEST" | xargs -0 sed -i "s|__PROJECT_NAME__|$NAME|g"
   ```

   Verify afterward that no `__PLACEHOLDER__` tokens remain:
   `grep -rn '__[A-Z_]*__' "$DEST"` should print nothing.

4. **Append language setup notes to `README.md`.** The shared README skeleton
   ends with a placeholder comment. Replace it with the concrete build/test
   commands for the chosen language, for example:
   - Python: `uv sync --dev`, `uv run pytest`, `uv run ruff check .`
   - Node: `npm install`, `npm test`, `npm run lint`
   - Go: `go test ./...`, `golangci-lint run`

5. **Initialize the repo and tooling.** Run in `$DEST`:
   - `git init` if not already a git repository.
   - Generate the lockfile / fetch deps for the language. This is what makes CI
     reproducible, since the CI workflows use locked installs:
     - Python: `uv sync --dev` (creates `uv.lock` — commit it; the CI `audit`
       job installs `--frozen` against it).
     - Node: `npm install` (creates `package-lock.json`, required by
       `npm ci` in CI and the audit job).
     - Go: `go mod tidy` (creates `go.sum`).

   Commit the lockfile — it is what makes both the build and the CI
   dependency audit reproducible.
   - Install the git hooks: `pre-commit install`. If `pre-commit` is not on the
     PATH, tell the user how to get it (`pipx install pre-commit` or
     `uv tool install pre-commit`) and continue without failing.

6. **Verify green.** Run the project's own checks once and report the result:
   - Python: `uv run ruff check . && uv run ruff format --check . && uv run pytest`
   - Node: `npm run lint && npm run format:check && npm run typecheck && npm test`
   - Go: `gofmt -l . && go vet ./... && go test ./...`

   If anything fails, fix the template output (or report clearly) before the
   commit — the whole point is a green starting line.

7. **Commit (ask first).** Show the user the file list and a proposed commit
   message, then, once they confirm, make the initial commit:

   ```text
   Initial commit: scaffold <language> project with linters, hooks, and CI
   ```

   Do not create a remote or push unless the user asks.

## Notes

- The scaffolded project's `.claude/settings.json` wires up two Claude Code
  hooks:
  - A `SessionStart` hook that best-effort installs dependencies (`uv sync`,
    `npm install`, `go mod download`) so a fresh clone or web session is ready
    to run.
  - A `PostToolUse` hook (matching `Edit|Write|MultiEdit`) that runs the shared
    `.claude/hooks/format.sh` to format the file Claude just edited — every time
    an edit finishes. It dispatches by extension: `ruff` (fix + format) for
    `.py`, `prettier` for JS/TS/JSON/CSS/Markdown/YAML, `gofmt` for `.go`, and
    `shfmt` for `.sh`/`.bash` (with no `-i` flag, so shfmt takes the indent
    width from the project's `.editorconfig`). It prefers project-local tools
    (the uv virtualenv's `ruff`, `node_modules/.bin/prettier`) over global
    installs so the project's pinned versions win. Both hooks are guarded to
    no-op (exit 0) when the relevant tool is absent, so editing is never
    blocked.
- Security tooling is on by default. The pre-commit config runs
  `detect-private-key` plus [gitleaks](https://github.com/gitleaks/gitleaks) to
  block hard-coded tokens, keys, and passwords, and each CI workflow has a
  separate `audit` job that scans locked dependencies for known
  vulnerabilities (`pip-audit` / `npm audit --audit-level=high` /
  `govulncheck`). This mirrors the DevSecOps posture in this repo's own
  `CLAUDE.md`: lock dependencies and audit them in CI.
- The templates pin linter/hook versions (e.g. `pre-commit` hook `rev`s). When
  they drift, bump them in `templates/<lang>/` — that is the single source of
  truth for every future project.
- Keep this skill's own scaffolding minimal and standard. Project-specific
  extras (Docker, frameworks, release automation) belong in the generated
  project, added after scaffolding — not baked into the template.
