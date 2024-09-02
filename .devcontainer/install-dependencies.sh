#!/bin/bash

sudo apt update
sudo apt install -y ansible python-is-python3
# To use git in dev containers.
git config --global --add safe.directory /workspaces/garaemon-settings
