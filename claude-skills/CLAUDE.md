# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Run CI checks locally before opening a PR

This repository enforces markdown lint and a README skills-link check in CI
(see `.github/workflows/ci.yml`). Run the same checks locally before
creating a pull request and fix any failures.

### Markdown lint

Run markdownlint-cli2 over all tracked Markdown files. The `REVIEW.md`
artifact produced by the code-review skill is explicitly excluded because
it is a local work product that is not committed:

```bash
npx --yes markdownlint-cli2 "**/*.md" "!REVIEW.md"
```

Configuration lives in `.markdownlint.json`. It keeps the default rule set
but disables `MD013` (line length), `MD033` (inline HTML), and `MD041`
(first-line heading) so docs with YAML frontmatter pass cleanly.

### README skills-link check

Run the Python script that verifies every skill under
`.claude/skills/<name>/SKILL.md` is linked from `README.md`. The script
uses only the Python 3 standard library, so no virtualenv or pip install
is needed:

```bash
python3 scripts/check-readme-skills.py
```

The script exits non-zero and lists the missing skill names if any skill
has no link in `README.md`. When you add a new skill, add an entry under
the `## Skills` section of `README.md` that links to its `SKILL.md`.

### Run both checks together

```bash
npx --yes markdownlint-cli2 "**/*.md" "!REVIEW.md" && python3 scripts/check-readme-skills.py
```
