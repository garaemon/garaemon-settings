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

### Pre-commit hooks

This repository uses [pre-commit](https://pre-commit.com/) with [detect-secrets](https://github.com/Yelp/detect-secrets) to prevent accidental credential commits.

```bash
brew install pre-commit  # or: mise use pre-commit, pipx install pre-commit
pre-commit install
```
