# garaemon-settings [![Lint](https://github.com/garaemon/garaemon-settings/actions/workflows/lint.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/lint.yml) [![Ansible Playbook](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml) [![Ansible Playbook macOS](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml)

Monorepo for garaemon's environment setup.

## Layout

- **ansible/**: Ansible playbooks and roles that provision the interactive
  desktop environment (packages, fonts, keyboard, editor toolchain).
- **claude-skills/**: Claude Code skills. `~/.claude/skills` is a symlink to
  `claude-skills/.claude/skills`. See [claude-skills/README.md](claude-skills/README.md).
- **dotfiles/**: chezmoi source for shell, git, editor, and terminal
  configuration. The root-level `.chezmoiroot` file points chezmoi at this
  subdirectory, so chezmoi commands need no `--source` flag. The root-level
  `install.sh` is a shim for GitHub Codespaces and Dev Containers that
  delegates to `dotfiles/install.sh`. See
  [dotfiles/README.md](dotfiles/README.md).
- **emacs.d/**: Emacs configuration. `~/.emacs.d` is a symlink to this
  directory, managed by chezmoi (`dotfiles/symlink_dot_emacs.d.tmpl`). See
  [emacs.d/README.md](emacs.d/README.md).

## Lint

Lint runs per language, not per subdirectory, so a file gets the same checks
wherever it lives in the monorepo. `.github/workflows/lint.yml` starts one job
per language, and every job calls the same script:

```sh
scripts/lint.sh
```

Pass targets to narrow the run: `shell`, `markdown`, `yaml`, `python`,
`ansible`, `whitespace`. Rule configuration lives at the repository root
(`.markdownlint.yaml`, `.yamllint.yaml`, `ruff.toml`), except where one dialect
needs its own: `dotfiles/.shellcheckrc` covers the zsh startup files, and
`ansible/.ansible-lint` covers the playbooks.

Tests stay with the component they exercise (`dotfiles-test.yml`,
`emacs-test.yml`, `skills-ci.yml`, `ansible.yml`).

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

## INSTALL

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings/ansible
ansible-playbook -i localhost, -c local main.yml --ask-become-pass
```

Ansible does not write the dotfiles. Apply them with chezmoi as described in
[Dotfiles](#dotfiles).

## Minimal Setup

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings/ansible
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass
```

## Dotfiles

`dotfiles/` holds the chezmoi source state. The `.chezmoiroot` file at the
repository root contains `dotfiles`, so chezmoi reads the source state from
that subdirectory and leaves `ansible/`, `emacs.d/`, and `claude-skills/`
alone.

Use the checkout that `ghq get` created as the chezmoi source, because
`~/.emacs.d` and `~/.claude/skills` are symlinks into it. Add `sourceDir` to
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
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings/ansible
ansible-playbook -i localhost, -c local ax8-max.yml --ask-become-pass
```
