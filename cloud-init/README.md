# cloud-init

Cloud-init user data for new virtual machines.

## OrbStack Ubuntu

`orbstack-ubuntu.yml` sets up an OrbStack Ubuntu machine with this repository.
Pass the file to `orb create`:

```sh
orb create ubuntu my-machine -c cloud-init/orbstack-ubuntu.yml
```

The user data runs these steps on the first boot:

1. Installs `curl`, `git`, `python3-venv`, and `zsh` through apt.
1. Starts `garaemon-bootstrap.service`. The unit waits for the user that
   OrbStack creates from your macOS account. OrbStack creates that user only
   after cloud-init finishes, so the bootstrap cannot run inside cloud-init.
1. Sets zsh as the login shell of that user.
1. Grants that user passwordless sudo, because `bootstrap.sh` runs without a
   terminal and cannot answer a password prompt.
1. Runs `bootstrap.sh --playbook orbstack` as that user. The orbstack
   playbook is the minimal playbook without the `font`, `enchant`,
   `ispell`, and `claude_code` roles. Like the minimal playbook, it skips
   the Emacs build.

The bootstrap takes a few minutes after `orb create` returns. Follow the
progress and check the result with:

```sh
orb -m my-machine sudo journalctl -u garaemon-bootstrap -f
orb -m my-machine systemctl status garaemon-bootstrap
```

`ansible/ansible.cfg` enables the `profile_tasks` callback, so the end of the
`garaemon-bootstrap` journal lists the slowest playbook tasks.
`orb -m my-machine cloud-init analyze blame` shows the time of each
cloud-init stage.

To get Emacs later, run the build inside the machine:

```sh
python3 ~/ghq/github.com/garaemon/garaemon-settings/emacs.d/scripts/build_emacs.py
```
