#!/usr/bin/env bash
# Thin shim for GitHub Codespaces / VS Code Dev Containers, which clone the
# dotfiles repository and run the root-level install.sh. The real installer
# lives in dotfiles/ since this repository became a monorepo.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotfiles/install.sh" "$@"
