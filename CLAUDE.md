# CLAUDE.md

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

# Minimal setup
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass

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