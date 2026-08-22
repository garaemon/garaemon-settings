# fingerprint_mafp

Builds and installs a libfprint TOD (Touch OEM Driver) module for the MicroArray
"MAFP General Device" fingerprint reader (USB `3274:8012`), which is not supported
by upstream libfprint/fprintd.

The driver is the reverse-engineered `jdillon/libfprint-microarray` driver,
compiled as a standalone TOD module so it drops a single `.so` into
`/usr/lib/<arch>/libfprint-2/tod-1/` without replacing the system
`libfprint-2.so`.

## What it does

- Installs the fprintd stack and TOD build dependencies via apt.
- Clones the driver source at a pinned revision and builds it with the
  role-provided `tod_glue.c` and `Makefile`.
- Installs the TOD module, a udev rule for non-root USB access, and (optionally)
  enables fingerprint authentication via PAM with the password kept as fallback.

Only runs on Debian/Ubuntu (`x86_64`).

## Variables

See `defaults/main.yml`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `fingerprint_mafp_enabled` | `true` | Build and install the driver. |
| `fingerprint_mafp_driver_repo` | jdillon repo | Upstream driver source. |
| `fingerprint_mafp_driver_version` | pinned commit | Revision built (reproducible). |
| `fingerprint_mafp_build_dir` | under `ghq` root | Clone/build directory. |
| `fingerprint_mafp_enable_pam` | `true` | Enable fingerprint login/sudo/unlock. |

## Enrolling a fingerprint

After the role runs, confirm the device is detected:

```bash
fprintd-list "$USER"        # lists enrolled fingers (or "no devices" if not detected)
```

Enroll a finger (default is `right-index-finger`):

```bash
fprintd-enroll                          # enrolls right-index-finger
fprintd-enroll -f left-index-finger     # enroll a specific finger
```

Press and lift the finger repeatedly until it reports `enroll-completed`
(6 samples). Valid finger names: `{left,right}-{thumb,index,middle,ring,little}-finger`.

The sensor stores up to 30 templates, so multiple fingers can be enrolled.

Verify the enrolled finger:

```bash
fprintd-verify              # should report verify-match for an enrolled finger
```

Delete enrolled fingerprints:

```bash
fprintd-delete "$USER"
```

## Using the fingerprint for login / sudo / unlock

PAM is enabled by the role (`fingerprint_mafp_enable_pam: true`). Once a finger
is enrolled, `sudo`, the login screen, and the screen-unlock prompt accept the
fingerprint, falling back to the password if it fails or times out. Test with:

```bash
sudo -k && sudo true        # should prompt for a fingerprint
```

## Troubleshooting

- **`No devices available` / not detected:** replug the reader, then
  `sudo systemctl restart fprintd`. Confirm the device is on the bus with
  `lsusb | grep 3274:8012`.
- **`AlreadyInUse: Device was already claimed`** (often after Ctrl-C during
  enroll): `sudo systemctl restart fprintd`, then retry.
- **Permission errors claiming the USB interface:** ensure the udev rule is
  loaded with `sudo udevadm control --reload-rules && sudo udevadm trigger`.

## Rollback

```bash
sudo pam-auth-update --disable fprintd
sudo rm /usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/libfprint-2/tod-1/libfprint-tod-mafp.so
sudo rm /etc/udev/rules.d/99-mafp.rules
sudo udevadm control --reload-rules
sudo systemctl restart fprintd
```

## Notes

This is a third-party, reverse-engineered driver. The source was audited for
unsafe memory handling and side effects before use; it is a pure USB protocol
implementation with no file/network/privilege access.
