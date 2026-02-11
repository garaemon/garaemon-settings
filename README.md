# garaemon-settings [![Ansible Lint](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml) [![Ansible Playbook](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml) [![Ansible Playbook macOS](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml)
some script to setup garaemon's environment

## INSTALL

### 1. Install Nix

```sh
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
```

### 2. Apply Nix Home Manager (git, gh, ghq, delta, etc.)

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings

# First time
nix run home-manager/release-25.05 -- switch --flake .#garaemon@mac       # macOS
nix run home-manager/release-25.05 -- switch --flake .#garaemon@linux-x86 # Ubuntu x86
nix run home-manager/release-25.05 -- switch --flake .#garaemon@linux-arm # Linux ARM

# Apply changes
home-manager switch --flake .#garaemon@mac
```

### 3. Run Ansible (remaining tools)

```sh
ansible-playbook -i localhost, -c local main.yml --ask-become-pass
```

## Minimal Setup

```sh
# After step 1 and 2 above
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass
```
