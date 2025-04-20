# garaemon-settings [![Build Status](https://travis-ci.org/garaemon/garaemon-settings.png)](https://travis-ci.org/garaemon/garaemon-settings)

some script to setup garaemon's environment

## INSTALL

```sh
git clone git@github.com:garaemon/garaemon-settings.git
cd garaemon-settings
ansible-playbook -i localhost, -c local main.yml --ask-become-pass --extra-vars="ansible_python_interpreter=/usr/bin/python3"
```

## Minimal Setup

```sh
git clone git@github.com:garaemon/garaemon-settings.git
cd garaemon-settings
ansible-playbook -i localhost, -c local minimal.yml --ask-become-pass --extra-vars="ansible_python_interpreter=/usr/bin/python3"
```
