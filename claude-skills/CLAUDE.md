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

## Run skill scripts inside Docker

Any skill that ships an executable (Node, Python, shell, compiled binary) must
run it inside a Docker container rather than directly on the host. This keeps
the host filesystem, network, and credentials off-limits even if the script
behaves badly or a transitive dependency is compromised.

If a skill only shells out to a CLI the user installed themselves (e.g.
`paperpile`), Docker is not required; the user's own install is the trust
boundary.

### Skill layout

```text
.claude/skills/<name>/
├── SKILL.md            # Skill definition; allowed-tools points at run.sh
├── Dockerfile          # Builds the execution image
├── package.json        # (or requirements.txt, go.mod, ...) pinned deps
├── <entrypoint>        # The actual CLI/script copied into the image
├── run.sh              # Thin wrapper that launches docker run
└── tests/
    └── smoke.sh        # Builds-and-runs sanity test invoked by CI
```

### Dockerfile conventions

- Pin the base image to a major tag (e.g. `node:22-slim`, `python:3.12-slim`).
- Install only `--omit=dev` / `--no-dev` runtime dependencies.
- Commit a lockfile and use a deterministic installer (`npm ci`,
  `pip install --require-hashes`, `uv sync --frozen`, etc.) — see
  [DevSecOps: lock dependencies and audit them in CI](#devsecops-lock-dependencies-and-audit-them-in-ci).
- Drop privileges with `USER node` (or a dedicated non-root UID) before the
  `ENTRYPOINT`.
- Use `ENTRYPOINT ["…"]` (not `CMD`) so extra args from `run.sh` are passed
  through as CLI arguments.
- Keep the image self-contained: the entrypoint script must resolve its
  dependencies from paths inside the image (`/app/node_modules`, a virtualenv,
  etc.), not from `NODE_PATH` or other ambient globals.

### `run.sh` wrapper conventions

`run.sh` is the only tool the skill exposes via `allowed-tools`, e.g.

```yaml
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/<name>/run.sh:*)
```

Every wrapper must:

1. Fail fast if the Docker image is missing, and print the exact
   `docker build` command the user should run (no auto-build — side effects
   on first invocation are surprising).
2. Validate all required environment variables up front.
3. For secret files (service-account keys, API tokens, etc.):
   - Default to `~/.config/<skill>/<name>.<ext>` and allow override via an
     env var.
   - Reject symlinks (`[[ -L "$path" ]]`) to prevent path confusion.
   - Require regular files (`[[ -f "$path" ]]`).
   - Require mode `600` or `400` (checked with `stat -c '%a'`, falling back
     to `stat -f '%Lp'` for portability).
   - Mount the file **read-only** (`-v "$path:/secrets/…:ro"`).
4. Launch the container with all of these isolation flags:

   ```bash
   docker run --rm \
     --network bridge \               # or --network none if no egress needed
     --read-only --tmpfs /tmp \
     --cap-drop ALL \
     --security-opt no-new-privileges \
     --memory 256m --cpus 0.5 \
     -v "$KEY_PATH:/secrets/…:ro" \
     -e <required env vars> \
     "$IMAGE_TAG" "$@"
   ```

   Only widen these defaults (higher memory, more mounts) when the skill
   documents a concrete reason.

### CI expectations for Docker-backed skills

`.github/workflows/ci.yml` runs these jobs that every Docker-backed skill must
satisfy:

- `shellcheck` — lints every `.claude/skills/**/*.sh` script. Run locally via
  `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable
  .claude/skills/<name>/run.sh .claude/skills/<name>/tests/smoke.sh`.
- A `<name>-image` job that runs `docker build` and then executes the
  skill's `tests/smoke.sh`.
- A per-language dependency audit job (e.g. `npm audit`) when the skill
  ships its own manifest — see
  [DevSecOps: lock dependencies and audit them in CI](#devsecops-lock-dependencies-and-audit-them-in-ci).

Smoke tests should at minimum confirm:

- The image starts and exits non-zero when required env vars are missing.
- The image prints usage (or equivalent help output) when invoked with no
  subcommand.

They must not require real credentials or network access to external
services.

## DevSecOps: lock dependencies and audit them in CI

Docker isolation (see above) limits the blast radius of a compromised
dependency at runtime, but it does not stop a malicious or vulnerable
package from being pulled into the image in the first place. Every skill
that ships its own dependency manifest (`package.json`, `requirements.txt`,
`go.mod`, `Cargo.toml`, ...) must therefore pin exact versions with a
lockfile and audit them on every PR.

### Commit the lockfile

- Always commit `package-lock.json` (or `Pipfile.lock`, `poetry.lock`,
  `go.sum`, `Cargo.lock`). Regenerate it whenever dependencies change.
- Regenerate a Node lockfile without touching `node_modules` with:

  ```bash
  npm install --package-lock-only --omit=dev
  ```

### Install deterministically inside the Dockerfile

- Node: `COPY package.json package-lock.json ./` then `RUN npm ci`
  (not `npm install`). `npm ci` refuses to run if the lockfile and
  manifest disagree, guaranteeing the image matches the committed state.
- Python: `pip install --require-hashes -r requirements.txt`, or
  `poetry install --no-root`, or `uv sync --frozen` — anything that
  errors on an out-of-date lock.

### Audit runtime dependencies in CI

Add a per-skill audit job that runs on every PR. Example for a Node skill:

```yaml
npm-audit:
  name: npm audit (spotify-sheets)
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-node@v4
      with:
        node-version: '22'
    - name: Audit production dependencies
      working-directory: .claude/skills/spotify-sheets
      run: npm audit --omit=dev --audit-level=high
```

- `--omit=dev` limits the scan to dependencies that actually ship inside
  the image.
- `--audit-level=high` fails on high/critical advisories only;
  low/moderate findings still surface in the job logs but do not block CI.
  Tighten to `--audit-level=moderate` when a skill handles particularly
  sensitive data.
- For Python, use `pip-audit` (or `safety check`) with an equivalent
  severity threshold.

When an advisory lands on `main`, the audit job starts failing — fix it
by bumping the affected package and regenerating the lockfile rather
than silencing the rule.
