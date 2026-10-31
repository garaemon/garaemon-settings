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

`dot_zshrc` sources two repositories:

- [rupa/z](https://github.com/rupa/z) for the `z` command.
- [seebi/dircolors-solarized](https://github.com/seebi/dircolors-solarized)
  for the `ls` colors.

`.chezmoiexternal.toml` clones both under `~/.local/share/` on
`chezmoi apply`. The clone needs neither sudo nor ghq, so machines that skip
the Ansible playbooks get them too. Keeping them out of `~/ghq` also keeps
them out of `ghq list`. chezmoi leaves an existing clone alone. To pull
updates, run:

```bash
chezmoi apply --refresh-externals \
  ~/.local/share/zsh/plugins/z ~/.local/share/dircolors-solarized
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

### tmux config reload

`chezmoi apply` runs
`.chezmoiscripts/run_onchange_after_reload-tmux-config.sh.tmpl` after it
installs `~/.tmux.conf`. The script runs `tmux source-file ~/.tmux.conf` so the
running tmux server picks up the new config. The script embeds a hash of
`dot_tmux.conf`, so chezmoi reruns it only when the config changes.

The script skips the reload in two cases:

- No tmux server runs. The next tmux start reads the new config anyway.
- chezmoi applies outside the login home, as the `install.sh` end-to-end test
  does.

### mise tool install

`chezmoi apply` runs
`.chezmoiscripts/run_onchange_after_install-mise-tools.sh.tmpl` after it
installs `~/.config/mise/config.toml`. The script runs `mise install --yes`, so
a tool added to the config, or a bumped version pin, arrives without a manual
install. chezmoi itself is one of those tools. The script embeds a hash of
`dot_config/mise/config.toml`, so chezmoi reruns it only when the config
changes. A tool pinned to `latest` therefore stays at its installed version
until you run `mise upgrade`.

The script skips the install in two cases:

- mise is not installed.
- chezmoi applies outside the login home, as the `install.sh` end-to-end test
  does.

### Slack digest timers (systemd --user, ax8-max only)

`dot_config/systemd/user/` holds the `systemd --user` timers that post the
`news-digest`, `spotify-daily-digest`, and `artist-live-digest` skills to
Slack. Each service runs a wrapper script inside
`~/ghq/github.com/garaemon/garaemon-settings/claude-skills/`, so the monorepo
must be checked out at that path.

The digests now run as Claude Code on the web routines. `chezmoi apply`
installs the units on ax8-max but leaves the timers disabled.
`.chezmoiignore.tmpl` skips the units on every other host.

Enable, inspect, or run a job by hand:

```bash
systemctl --user enable --now news-digest-slack.timer
systemctl --user list-timers '*-slack.timer'
journalctl --user -u news-digest-slack.service -n 200 --no-pager
systemctl --user start news-digest-slack.service
```

### Claude Code plugins

`dot_claude/modify_settings.json` is a chezmoi modify template. It merges
these keys into `~/.claude/settings.json` and leaves every other key alone:

- `extraKnownMarketplaces`: registers the `ayghri/i-have-adhd` marketplace.
- `enabledPlugins`: enables `i-have-adhd@i-have-adhd`.
- `hooks.SessionEnd`: appends the worklog hook described in
  [Claude Code worklog](#claude-code-worklog). The template keeps any other
  SessionEnd hook and adds the worklog hook only once.

The template uses chezmoi's built-in `fromJson`, `setValueAtPath`, and
`toPrettyJson` functions, so it needs no external command such as `jq`.
`bootstrap.sh` applies the dotfiles before mise installs `jq`. The rendered
file lists its keys in alphabetical order. Add further plugins with more
`setValueAtPath` calls in the template.

### Claude Code worklog

`dot_claude/hooks/executable_claude_worklog.py` installs to
`~/.claude/hooks/claude_worklog.py`. Claude Code runs the script when a
session ends. The script logs the session in the org-roam daily note so that
the work shows up in org-agenda:

1. The hook returns at once and hands the work to a detached child process.
1. The child reads the transcript of the day and asks `claude -p --model haiku`
   for a short Japanese summary. The first prompt becomes the title when the
   summary fails.
1. The child writes one entry into `$ORG_DIR/org-roam/daily/YYYY-MM-DD.org`.
   `ORG_DIR` defaults to `~/ghq/github.com/garaemon/org`.

Each entry looks like this:

```org
* <2026-10-31 Sat 14:02> garaemon-settings: <title> :claude:worklog:
:PROPERTIES:
:GENERATED_BY: claude-code/worklog
:SESSION_ID: <session id>
:CWD: /path/to/repository
:BRANCH: <branch>
:END:
:LOGBOOK:
CLOCK: [2026-10-31 Sat 14:02]--[2026-10-31 Sat 14:47] =>  0:45
:END:
- <what was done>
```

The entry has these properties:

- The active timestamp puts the entry on the agenda day view.
- The CLOCK lines feed the agenda log mode and clock tables. An idle gap over
  30 minutes splits the session into separate CLOCK lines.
- A resumed session replaces its own entry of the same day, matched by
  `SESSION_ID`, instead of adding a duplicate.

The hook does nothing when the org-roam directory is missing, as in a cloud
container. The summarizer sets `CLAUDE_WORKLOG_RUNNING`, so its own session
does not trigger the hook again.

### Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) with [detect-secrets](https://github.com/Yelp/detect-secrets) to prevent accidental credential commits.

```bash
brew install pre-commit  # or: mise use pre-commit, pipx install pre-commit
pre-commit install
```
