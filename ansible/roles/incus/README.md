# incus

Installs Incus from the [Zabbly](https://github.com/zabbly/incus) apt
repository. The Ubuntu archive ships an older Incus that does not get feature
updates.

## What it does

- Installs the Zabbly signing key into `/etc/apt/keyrings/`, pinned by its
  SHA-256 checksum.
- Registers the Zabbly repository for the `incus_channel` channel.
- Installs the `incus` package.
- Adds `incus_admin_user` to the `incus-admin` group.
- Lets traffic through ufw on the Incus bridge. Without these rules, ufw drops
  the DHCP, DNS, and forwarded traffic of instances.

Only runs on Debian/Ubuntu.

## Variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `incus_channel` | `lts-6.0` | `stable` or `lts-6.0`. You cannot move from `stable` back to an LTS channel. |
| `incus_admin_user` | the user that runs the playbook | User to add to `incus-admin`. |
| `incus_bridge_interface` | `incusbr0` | Bridge that the ufw rules allow. |

## After the first run

The role does not initialize Incus, because `incus admin init` is interactive.
Run these steps once:

1. Log out and back in, so that the `incus-admin` group takes effect.
1. Run `incus admin init`. It creates the storage pool and the `incusbr0`
   bridge.

When the Zabbly key expires (2030-08), update the checksum in
`tasks/main.yml`.
