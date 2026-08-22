#!/bin/bash

sudo apt update
sudo apt install -y curl

# Install uv
curl -LsSf https://astral.sh/uv/install.sh | sh

# Add uv to path for the current session (it usually installs to ~/.local/bin or ~/.cargo/bin)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Install ansible and ansible-lint using uv
uv tool install --with ansible ansible-core
uv tool install ansible-lint

# To use git in dev containers.
git config --global --add safe.directory /workspaces/garaemon-settings
