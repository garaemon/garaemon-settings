# garaemon-settings [![Ansible Lint](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml) [![Ansible Playbook](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml) [![Ansible Playbook macOS](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml)

some script to setup garaemon's environment

## Scope

This repository configures the **interactive desktop environment** of a host,
set up locally (editor, shell, keyboard, fonts, fingerprint reader, etc.). Some
machines, such as `ax8-max`, are also configured in
[`private-server-config`](https://github.com/garaemon/private-server-config).
The boundary is the concern, not the machine:

- **garaemon-settings** (this repo): the interactive desktop environment of a
  host that is set up locally.
- **private-server-config**: headless server services for a host, managed
  remotely over SSH (Docker, Prometheus, Jenkins, Jupyter, Plex, Tailscale,
  etc.).

Device- and login-oriented settings (for example the MAFP fingerprint reader on
`ax8-max`) belong here, not in `private-server-config`.

## INSTALL

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings
ansible-playbook -i localhost, -c local main.yml --ask-become-pass
```

## Minimal Setup

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass
```

## Host-specific Setup

### ax8-max

Runs `main.yml` plus host-specific roles for the ax8-max machine (e.g. the
MicroArray MAFP fingerprint reader, see `roles/fingerprint_mafp`).

```sh
ghq get git@github.com:garaemon/garaemon-settings.git
cd $(ghq root)/github.com/garaemon/garaemon-settings
ansible-playbook -i localhost, -c local ax8-max.yml --ask-become-pass
```
