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

`.github/workflows/ci.yml` runs two jobs that every Docker-backed skill must
satisfy:

- `shellcheck` — lints every `.claude/skills/**/*.sh` script. Run locally via
  `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable
  .claude/skills/<name>/run.sh .claude/skills/<name>/tests/smoke.sh`.
- A `<name>-image` job that runs `docker build` and then executes the
  skill's `tests/smoke.sh`.

Smoke tests should at minimum confirm:

- The image starts and exits non-zero when required env vars are missing.
- The image prints usage (or equivalent help output) when invoked with no
  subcommand.

They must not require real credentials or network access to external
services.
