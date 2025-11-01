# garaemon-settings [![Ansible Lint](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-lint.yml) [![Ansible Playbook](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible.yml) [![Ansible Playbook macOS](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/ansible-macos.yml)

some script to setup garaemon's environment

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
