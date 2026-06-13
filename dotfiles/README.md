# dotfiles

My dotfiles managed by chezmoi

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply garaemon
```

To install chezmoi, you can use mise.

```bash
mise use -g chezmoi
```

## Setup

### VS Code Dev Containers / GitHub Codespaces

This repository can be used as a [dotfiles
repository](https://code.visualstudio.com/docs/devcontainers/containers#_personalizing-with-dotfile-repositories)
for VS Code Dev Containers and GitHub Codespaces. Configure the repo URL in
your VS Code settings (`dotfiles.repository`) or Codespaces settings; the
container will clone it and run `install.sh`, which installs chezmoi and
applies the dotfiles.

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

### Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) with [detect-secrets](https://github.com/Yelp/detect-secrets) to prevent accidental credential commits.

```bash
brew install pre-commit  # or: mise use pre-commit, pipx install pre-commit
pre-commit install
```
