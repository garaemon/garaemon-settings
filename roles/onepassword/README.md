# onepassword

Installs the 1Password desktop app from the official apt repository.

The `.deb` package is preferred over Flatpak/Snap because system
authentication (polkit) integration works reliably only with the native
package.

## What it does

- Skips everything when the `1password` command already exists.
- Installs the 1Password signing key into `/usr/share/keyrings/`.
- Registers the official apt repository with `signed-by`.
- Installs the `1password` package.

Only runs on Debian/Ubuntu (`x86_64`).

## Unlocking with a fingerprint

1Password unlocks through polkit and PAM. If `pam_fprintd.so` is enabled in
`/etc/pam.d/common-auth` (see the `fingerprint_mafp` role) and a finger is
enrolled, follow these steps:

1. Open 1Password and sign in with the master password.
2. Go to Settings > Security and enable "Unlock using system authentication".
3. Lock 1Password and unlock it again. The polkit dialog accepts the
   fingerprint.

Notes:

- The master password is always required after a reboot or the first app
  launch. The fingerprint only re-unlocks a session that was unlocked once.
- To let the `op` CLI reuse the app unlock, enable
  Settings > Developer > "Integrate with 1Password CLI".

## Troubleshooting

- **The unlock dialog only asks for a password:** confirm that polkit reaches
  the fingerprint PAM module. Without `/etc/pam.d/polkit-1`, PAM falls back to
  `/etc/pam.d/other`, which includes `common-auth`.
- **The fingerprint prompt does not appear:** verify enrollment with
  `fprintd-verify` and check `systemctl status fprintd`.
