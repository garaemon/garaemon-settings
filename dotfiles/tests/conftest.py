"""Shared pytest setup for the dotfiles tests."""

import sys

# Tests import scripts straight from the chezmoi source tree, where a
# __pycache__ directory would be installed into $HOME as managed files.
sys.dont_write_bytecode = True
