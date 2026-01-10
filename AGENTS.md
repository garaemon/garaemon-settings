# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible-based dotfiles and system configuration repository for setting up development environments on macOS and Linux. The repository uses Ansible playbooks to automate the installation and configuration of development tools, shell environments, and applications.

## Architecture

- **main.yml**: Full system setup playbook with all roles
- **minimal.yml**: Minimal setup playbook with essential tools only
- **roles/**: Individual Ansible roles for specific tools/configurations
  - Each role follows standard Ansible structure (tasks/main.yml, files/, defaults/, etc.)
- **resources/**: Configuration files and templates used by roles

## Common Commands

### Setup and Installation
```bash
# Full setup
ansible-playbook -i localhost, -c local main.yml --ask-become-pass

# Minimal setup (can run without sudo if git is already installed)
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass

# Minimal setup without sudo (when git is pre-installed)
ansible-playbook -i localhost, -c local minimal.yml

# Install specific role
ansible-playbook -i localhost, -c local --tags "role_name" main.yml --ask-become-pass
```

### Development and Testing
```bash
# Lint Ansible playbooks
ansible-lint

# Check syntax without running
ansible-playbook --syntax-check main.yml

# Dry run to see what would change
ansible-playbook -i localhost, -c local main.yml --check
```

## Key Roles

The repository includes roles for:
- **base**: Essential system packages and configurations
- **zsh**: Shell setup with custom configurations
- **emacs**: Emacs installation and configuration
- **git**: Git setup with hooks and configurations
- **tmux/vim**: Terminal multiplexer and editor setup
- **homebrew**: macOS package manager (Darwin only)
- **apt**: Package installation (Debian/Ubuntu only)

## Platform Support

Roles use Ansible conditionals for cross-platform compatibility:
- `ansible_os_family == "Darwin"` for macOS-specific tasks
- `ansible_os_family == "Debian"` for Linux-specific tasks
- `ansible_architecture != 'aarch64'` for architecture-specific exclusions

## Sudo Policy

### minimal.yml
- **Can run without sudo** when git is already installed on the system
- Only requires sudo for git package installation on Debian/Ubuntu systems
- The git role checks if git is installed before attempting installation with sudo
- All other roles (dotfiles, symlinks, configurations) run without sudo privileges

### main.yml
- **Requires sudo** for package installation and system-level configuration
- Uses `--ask-become-pass` flag for elevated privileges
- Installs system packages via apt (Linux) or homebrew (macOS)

## Memories

- Check the code by linter every time you change the code by `act -j lint`.