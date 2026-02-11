# Nix Migration Status

This document tracks the status of migrating Ansible roles to Nix (Home Manager).

## Environment Specific TODOs

### System Configuration (Requires Root/Sudo)
These configurations might require `nix-darwin` (macOS) or system-level configuration (NixOS / manual on Ubuntu).

- [ ] `apt` packages replacement (System dependencies like `build-essential`, `libgnutls-dev`)
- [ ] `sudo_no_password` (Can be managed by `nix-darwin` on macOS, manual/Ansible on Ubuntu)
- [ ] `keyd` configuration (Service management on Linux)
- [ ] `ghostty_install` (System-wide install?)

### macOS (User)
- [ ] Install Ghostty (via Homebrew Cask in `nix-darwin` or Home Manager if available)
- [ ] Configure Karabiner-Elements
- [ ] Font installation

### Ubuntu (User)
- [ ] Gnome Terminal colors (`base16_gnome_terminal`)

## Multi-Environment & Private Configuration

The `flake.nix` is configured to support multiple environments (e.g., Home, Work) with different user details.

### Supported Platforms

| Name | system | homeDirectory |
|:---|:---|:---|
| `garaemon@mac` | `aarch64-darwin` | `/Users/garaemon` |
| `garaemon@linux-x86` | `x86_64-linux` | `/home/garaemon` |
| `garaemon@linux-arm` | `aarch64-linux` | `/home/garaemon` |

Usage:
```bash
home-manager switch --flake .#garaemon@mac
home-manager switch --flake .#garaemon@linux-x86
home-manager switch --flake .#garaemon@linux-arm
```

### How to add a new environment

Edit `flake.nix` to add a new configuration to `homeConfigurations`.

```nix
homeConfigurations = {
  "work-machine" = mkHomeConfig {
    username = "work_user";
    email = "work@example.com";
    homeDirectory = "/Users/work_user";
    system = "aarch64-darwin";
    privateConfigPath = ./private/work.nix;
  };
};
```

### Private Configuration

You can place sensitive configuration (e.g., work-specific settings, API keys) in a file within the `private/` directory. This directory is git-ignored.

Example `private/work.nix`:

```nix
{ ... }:
{
  programs.git.userName = "Work User Name";
  # Add other work-specific settings here
}
```

## Role Migration Matrix

**Scope:**
- **User**: Managed by Home Manager (`home.nix`).
- **System**: Requires root access (e.g., `/etc/`, system services). Managed by `nix-darwin` (macOS) or Ansible/Manual (Ubuntu).

| Role | Scope | Migration Status | Ubuntu | Mac | Notes |
|:---|:---:|:---:|:---:|:---:|:---|
| agg | User | [ ] | [ ] | [ ] | |
| apt | System/User | [ ] | [ ] | - | Ubuntu specific. User tools (e.g. `htop`, `ripgrep`) -> User. System deps -> System. |
| base | User | [ ] | [ ] | [ ] | Common packages |
| base16_gnome_terminal | User | [ ] | [ ] | - | Gnome Terminal specific |
| ccls | User | [ ] | [ ] | [ ] | C/C++ LSP |
| chrome | User | [ ] | [ ] | [ ] | Browser |
| circleci_cli | User | [ ] | [ ] | [ ] | CLI tool |
| clang_format | User | [ ] | [ ] | [ ] | Formatter |
| clangd | User | [ ] | [ ] | [ ] | C/C++ LSP |
| coding_agent | User | [ ] | [ ] | [ ] | AI coding tools |
| dictd | System | [ ] | [ ] | [ ] | Dictionary server (Service) |
| dircolors_solarized | User | [ ] | [ ] | [ ] | Shell colors |
| emacs | User | [ ] | [ ] | [ ] | Editor |
| enchant | User | [ ] | [ ] | [ ] | Spell checker |
| font | User | [ ] | [ ] | [ ] | Fonts (User installed) |
| gh | User | [x] | [x] | [x] | `programs.gh` |
| ghostty | User | [ ] | [ ] | [ ] | Terminal Emulator |
| ghostty_install | System | [ ] | [ ] | [ ] | Installation script |
| ghq | User | [x] | [x] | [x] | `pkgs.ghq` |
| git | User | [x] | [x] | [x] | `programs.git` (Includes `delta` via options) |
| git_find_big | User | [ ] | [ ] | [ ] | Git utility |
| homebrew | System | [ ] | - | [ ] | Package manager (Mac) |
| ispell | User | [ ] | [ ] | [ ] | Spell checker |
| karabiner | User | [ ] | - | [ ] | Key remapper (Mac) |
| keyboard | User | [ ] | [ ] | [ ] | Keyboard settings |
| keyd | System | [ ] | [ ] | - | Key remapper (Linux Service) |
| mise | User | [ ] | [ ] | [ ] | Runtime version manager |
| peco | User | [ ] | [ ] | [ ] | Interactive filtering tool |
| python_language_server | User | [ ] | [ ] | [ ] | Python LSP |
| starship | User | [ ] | [ ] | [ ] | Shell prompt |
| sudo_no_password | System | [ ] | [ ] | [ ] | Sudo configuration |
| tig | User | [ ] | [ ] | [ ] | Git TUI |
| tmux | User | [ ] | [ ] | [ ] | Terminal multiplexer |
| typescript_language_server | User | [ ] | [ ] | [ ] | TypeScript LSP |
| uv | User | [ ] | [ ] | [ ] | Python package installer |
| vim | User | [ ] | [ ] | [ ] | Editor |
| vscode | User | [ ] | [ ] | [ ] | Editor |
| zsh | User | [ ] | [ ] | [ ] | Shell |

## Architecture Note

Current setup uses **Home Manager** via flak for user-level configuration.
For system-level configuration (e.g. `sudoers`, `services`):
- **macOS**: Consider adopting `nix-darwin`.
- **Ubuntu**: Continue using Ansible for system bootstrap, or manage manually. Nix on non-NixOS Linux has limited system management capabilities.
