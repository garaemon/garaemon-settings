# dotfiles

My dotfiles managed by chezmoi, inside the `garaemon-settings` monorepo.

To install chezmoi, you can use mise.

```bash
mise use -g chezmoi
```

## Source directory

This directory, not the repository root, is the chezmoi source directory. The
`.chezmoiroot` file at the repository root contains `dotfiles`, so chezmoi
reads the source state from here and leaves `ansible/`, `emacs.d/`, and
`claude-skills/` alone.

### Existing monorepo checkout

Prefer this over a fresh clone. `~/.emacs.d` and `~/.claude/skills` are
symlinks into `~/ghq/github.com/garaemon/garaemon-settings`, so a second copy
of the repository under `~/.local/share/chezmoi` only adds a checkout to keep
in sync.

Add `sourceDir` to `~/.config/chezmoi/chezmoi.toml`. Put it above every
`[table]` header, because TOML reads a bare key below a header as a member of
that table:

```toml
sourceDir = "~/ghq/github.com/garaemon/garaemon-settings"
```

Then review and apply:

```bash
chezmoi diff
chezmoi apply
```

### Fresh clone

`chezmoi init` clones the whole monorepo into `~/.local/share/chezmoi` and
still finds the source state through `.chezmoiroot`:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply garaemon/garaemon-settings
```

The `~/.emacs.d` and `~/.claude/skills` symlinks dangle until you also run
`ghq get git@github.com:garaemon/garaemon-settings.git`.

## Setup

### VS Code Dev Containers / GitHub Codespaces

This repository can be used as a [dotfiles
repository](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)
for VS Code Dev Containers and GitHub Codespaces. Configure the monorepo URL
(`garaemon/garaemon-settings`) in your VS Code settings
(`dotfiles.repository`) or Codespaces settings; the container will clone it
and run the root-level `install.sh` shim, which delegates to
`dotfiles/install.sh`, installs chezmoi, and applies the dotfiles with
`chezmoi apply --source=`.

The container image must include `bash` (4 or later, for associative
arrays) and `curl`. Most popular base images (Debian/Ubuntu, the Codespaces
default) ship them; minimal images (`alpine`, `distroless`) need them
installed first (e.g. `apk add --no-cache bash curl`).

`install.sh` pins a specific chezmoi version and verifies the release tarball
against an embedded sha256 checksum, so an upstream or network compromise
cannot install a tampered binary. To bump the pinned version, update
`CHEZMOI_VERSION` and `CHEZMOI_CHECKSUMS` in `install.sh` from the official
`chezmoi_<version>_checksums.txt` published with each GitHub release.

#### Installing CLI tools (`--tools`)

By default `install.sh` only installs chezmoi and applies the dotfiles. Pass
`--tools` to also install a set of CLI tools (starship, etc.) through a
pinned, sha256-verified [mise](https://mise.jdx.dev/) release — handy for
bringing a fresh dev container up to a usable interactive shell in one shot:

```bash
./install.sh --tools          # minimal set (same as --tools=minimal)
./install.sh --tools=minimal  # starship, bat, ripgrep, delta, direnv, jq, peco, ghq
./install.sh --tools=all      # every tool in dot_config/mise/config.toml
```

Tool versions come from `dot_config/mise/config.toml`, so they match what
mise installs in day-to-day use. `--tools=all` pulls in heavier
language/cloud toolchains (go, node, gcloud, …) and takes longer.

To use this from VS Code Dev Containers, point `dotfiles.installCommand` at
`install.sh --tools` (the default install command runs `install.sh` with no
arguments). Run `./install.sh --help` for the full option list.

Like chezmoi, the mise version is pinned and the release tarball is verified
against an embedded sha256 checksum (`MISE_VERSION` and `MISE_CHECKSUMS` in
`install.sh`); bump them from the release's `SHASUMS256.txt`.

#### Shell plugin repositories (`.chezmoiexternal.toml`)

`dot_zshrc` sources two repositories from the ghq tree:

- [rupa/z](https://github.com/rupa/z) for the `z` command.
- [seebi/dircolors-solarized](https://github.com/seebi/dircolors-solarized)
  for the `ls` colors.

`.chezmoiexternal.toml` clones both into `~/ghq/github.com/` on
`chezmoi apply`. The clone needs no sudo, so machines that skip the Ansible
playbooks get them too. chezmoi leaves an existing clone alone. To pull
updates, run:

```bash
chezmoi apply --refresh-externals ~/ghq
```

### Machine-local configuration (atuin sync)

Some settings are personal and must not be committed to this public repository
(for example the [atuin](https://atuin.sh/) sync server address). These are
templated out of the tracked files and read from chezmoi's machine-local
configuration, which lives at `~/.config/chezmoi/chezmoi.toml` and is never
part of this repo.

To enable atuin sync on a machine, create `~/.config/chezmoi/chezmoi.toml`
with the sync server address:

```toml
[data.atuin]
  syncAddress = "https://your-sync-server.example/atuin"
```

Then apply:

```bash
chezmoi apply ~/.config/atuin/config.toml
```

`dot_config/atuin/private_config.toml.tmpl` only emits the `sync_address` line
when `atuin.syncAddress` is set. On a machine without this local config the
line is omitted entirely and `chezmoi apply` still succeeds, so atuin simply
runs without a sync server.

### Slack digest timers (systemd --user, ax8-max only)

`dot_config/systemd/user/` holds the `systemd --user` timers that post the
`news-digest`, `spotify-daily-digest`, and `artist-live-digest` skills to
Slack. Each service runs a wrapper script inside
`~/ghq/github.com/garaemon/garaemon-settings/claude-skills/`, so the monorepo
must be checked out at that path.

`chezmoi apply` installs the units and then runs
`.chezmoiscripts/run_onchange_after_enable-slack-digest-timers.sh.tmpl`, which
reloads systemd and enables the timers. The script embeds a hash of every unit
file, so chezmoi reruns it whenever a unit changes.

Only ax8-max runs these digests, so `.chezmoiignore.tmpl` skips both the units
and the script on every other host. The script itself also exits early in two
cases:

- No systemd user manager answers, for example over an ssh session before
  lingering is enabled.
- chezmoi applies outside the login home, where the manager would never see the
  units. This case keeps the `install.sh` end-to-end test green on ax8-max.

Inspect or run the jobs by hand:

```bash
systemctl --user list-timers '*-slack.timer'
journalctl --user -u news-digest-slack.service -n 200 --no-pager
systemctl --user start news-digest-slack.service
```

To stop a job on one machine, disable its timer. chezmoi re-enables it only
when a unit file changes:

```bash
systemctl --user disable --now news-digest-slack.timer
```

### Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) with [detect-secrets](https://github.com/Yelp/detect-secrets) to prevent accidental credential commits.

```bash
brew install pre-commit  # or: mise use pre-commit, pipx install pre-commit
pre-commit install
```
