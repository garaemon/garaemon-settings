# garaemon-settings [![Lint](https://github.com/garaemon/garaemon-settings/actions/workflows/lint.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/lint.yml) [![Ansible Playbook](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml) [![Ansible Playbook macOS](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml)

Monorepo for garaemon's environment setup.

## INSTALL

Run one command on a fresh machine. The command needs only `bash` and `curl`:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/garaemon/garaemon-settings/main/bootstrap.sh)"
```

You do not need ghq, chezmoi, or Ansible beforehand. `bootstrap.sh` runs these
steps, and each step skips work that is already done:

1. Installs the prerequisites: `git`, `curl`, and `python3-venv` through apt on
   Debian-based Linux, or bash 4+ through Homebrew on macOS.
1. Clones this repository with plain `git` into
   `~/ghq/github.com/garaemon/garaemon-settings`. The `~/.emacs.d` and
   `~/.claude/skills` symlinks point at this path, so the checkout must live
   there.
1. Adds `sourceDir` to `~/.config/chezmoi/chezmoi.toml`, then runs
   `dotfiles/install.sh --tools`. That script applies the dotfiles with a
   pinned chezmoi and installs the minimal CLI tools, ghq among them, through
   a pinned mise.
1. Installs Ansible into a virtualenv under
   `~/.local/share/garaemon-settings/ansible-venv` and runs
   `ansible/main.yml`. The playbook prompts for the sudo password unless sudo
   works without one.

Pass arguments after a placeholder `$0` such as `bootstrap`:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/garaemon/garaemon-settings/main/bootstrap.sh)" \
  bootstrap --playbook minimal
```

The script accepts these options:

- `--playbook main|minimal|ax8-max`: selects the playbook. The default is
  `main`.
- `--skip-dotfiles`: skips step 3.
- `--skip-ansible`: skips step 4.
- `--no-sudo`: never uses sudo, even when it is installed.
- `--build-emacs`: builds Emacs from source into `~/.local` after the other
  steps. The build needs no root and runs on Linux only. See
  [Building Emacs](emacs.d/README.md#building-emacs).

The script also runs without root, for example in a container that has no
`sudo` command, or with `--no-sudo`. In that case it runs these steps only:

- It clones the repository (step 2).
- It applies the dotfiles and installs the CLI tools under `~/.local` (step 3).

Steps 1 and 4 install system packages, so the script handles them this way:

- Step 1 fails with the list of missing packages when `git` or `curl` is
  missing. Ask an administrator to install them.
- Step 4 is skipped, because every playbook installs packages as root.

Pass `--build-emacs` to get Emacs on such a host, because the playbook that
normally builds it does not run there.

Use `bash -c "$(curl ...)"`, not `curl ... | bash`. A pipe replaces stdin, so
the sudo and Ansible password prompts cannot read the keyboard.

On macOS, install the Xcode Command Line Tools (`xcode-select --install`) and
[Homebrew](https://brew.sh) first. The script stops with a message when either
is missing.

The clone uses HTTPS because a fresh machine has no GitHub SSH key yet. After
you register a key, switch the remote:

```sh
git -C ~/ghq/github.com/garaemon/garaemon-settings remote set-url origin \
  git@github.com:garaemon/garaemon-settings.git
```

To rerun a playbook later from the checkout, call the script directly:

```sh
~/ghq/github.com/garaemon/garaemon-settings/bootstrap.sh --skip-dotfiles --playbook minimal
```

## Layout

- **ansible/**: Ansible playbooks and roles that provision the interactive
  desktop environment (packages, fonts, keyboard, editor toolchain).
- **claude-skills/**: Claude Code skills. `~/.claude/skills` is a symlink to
  `claude-skills/skills`, and the repository-root `.claude/skills` is a
  second, committed symlink to the same directory. The committed one survives a
  fresh clone, so a container that never runs chezmoi, such as Claude Code on
  the web, still loads every skill.
  See [claude-skills/README.md](claude-skills/README.md).
- **dotfiles/**: chezmoi source for shell, git, editor, and terminal
  configuration. The root-level `.chezmoiroot` file points chezmoi at this
  subdirectory, so chezmoi commands need no `--source` flag. The root-level
  `install.sh` is a shim for GitHub Codespaces and Dev Containers that
  delegates to `dotfiles/install.sh`. See
  [dotfiles/README.md](dotfiles/README.md).
- **emacs.d/**: Emacs configuration, which requires Emacs 31.1 or later.
  `~/.emacs.d` is a symlink to this directory, managed by chezmoi
  (`dotfiles/symlink_dot_emacs.d.tmpl`). See
  [emacs.d/README.md](emacs.d/README.md).

## Lint

Lint runs per language, not per subdirectory, so a file gets the same checks
wherever it lives in the monorepo. `.github/workflows/lint.yml` starts one job
per language, and every job calls the same script:

```sh
scripts/lint.sh
```

A linter also holds a coding agent to the conventions in `CLAUDE.md`. An agent
reads an instruction once and drifts; a failing check stops the branch. Prefer
encoding a rule as a lint rule whenever the linter can express it.

Pass targets to narrow the run: `shell`, `markdown`, `javascript`, `yaml`,
`python`, `ansible`, `whitespace`. Rule configuration lives at the repository
root (`.markdownlint.yaml`, `eslint.config.mjs`, `.yamllint.yaml`, `ruff.toml`),
except where one dialect needs its own: `dotfiles/.shellcheckrc` covers the zsh
startup files, and `ansible/.ansible-lint` covers the playbooks.

Every target but `javascript` fetches its linter on demand. ESLint instead reads
its plugins from this repository's `node_modules`, so install them once before
the first run:

```sh
npm ci
```

ESLint covers `.js`, `.mjs`, `.cjs`, and the JavaScript inlined in `.html`,
which `eslint-plugin-html` extracts. Beyond the recommended rule set it enforces
`no-var` and `prefer-const`; both are auto-fixable with
`npx eslint --fix <file>`.

Tests stay with the component they exercise (`dotfiles-test.yml`,
`emacs-test.yml`, `emacs-build-test.yml`, `skills-ci.yml`, `ansible.yml`).

## Scope

This repository configures the **interactive desktop environment** of a host,
set up locally (editor, shell, keyboard, fonts, fingerprint reader, etc.). Some
machines, such as `ax8-max`, are also configured in
[`private-server-config`](https://github.com/garaemon/private-server-config).
The boundary is the concern, not the machine:

- **garaemon-settings** (this repo): the interactive desktop environment of a
  host that is set up locally.
- **private-server-config**: headless server services for a host, managed
  remotely over SSH (Docker, Prometheus, Jenkins, Jupyter, Plex, Tailscale,
  etc.).

Device- and login-oriented settings (for example the MAFP fingerprint reader on
`ax8-max`) belong here, not in `private-server-config`.

## Dotfiles

`dotfiles/` holds the chezmoi source state. The `.chezmoiroot` file at the
repository root contains `dotfiles`, so chezmoi reads the source state from
that subdirectory and leaves `ansible/`, `emacs.d/`, and `claude-skills/`
alone.

`bootstrap.sh` configures chezmoi for you. To set it up by hand, use the
checkout under `~/ghq` as the chezmoi source, because `~/.emacs.d` and
`~/.claude/skills` are symlinks into it. Add `sourceDir` to
`~/.config/chezmoi/chezmoi.toml`, above every `[table]` header:

```toml
sourceDir = "~/ghq/github.com/garaemon/garaemon-settings"
```

Then review and apply:

```sh
chezmoi diff
chezmoi apply
```

See [dotfiles/README.md](dotfiles/README.md) for dev container setup and
machine-local configuration.

## Host-specific Setup

### ax8-max

Runs `main.yml` plus host-specific roles for the ax8-max machine (e.g. the
MicroArray MAFP fingerprint reader, see `ansible/roles/fingerprint_mafp`).

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/garaemon/garaemon-settings/main/bootstrap.sh)" \
  bootstrap --playbook ax8-max
```
