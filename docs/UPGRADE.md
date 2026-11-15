# Upgrade — Squeezebox RG35XX H (0.2.0-exp2)

There is **no OTA or in-place upgrade** in 0.2.0-exp2: no A/B slots, no
recovery partition, no package feed for our payload. Upgrading (or
downgrading) means backing up device state and re-flashing the new image
([INSTALL.md](INSTALL.md)). An update story is WP4/WP5 work.

## Before you upgrade

1. Note the running version and variant:

```sh
cat /etc/os-release
```

2. Back up everything listed in [RECOVERY.md](RECOVERY.md#what-to-back-up)
   (`/etc/squeezebox/`, `/etc/wpa_supplicant/wpa_supplicant.conf`,
   `/root/.ssh/authorized_keys`, `/etc/ssh/ssh_host_*`,
   `/var/lib/squeezebox/`). Keep the backup off the card.
3. Download the new release dir and verify it:

```sh
sha256sum -c SHA256SUMS
# or: bash releases/checksum.sh verify <release-dir>
```

4. Confirm the new `MANIFEST.json` (`version`, `variant`, `git_commit`)
   matches the release you intended
   (shape: [releases/MANIFEST.template.json](../releases/MANIFEST.template.json)).

## Upgrade steps

1. Re-flash the card with the new image for your DRAM variant
   ([INSTALL.md](INSTALL.md#3-flash)). If the new release renamed
   images, follow its own INSTALL.md.
2. Boot once and let first-boot finalization finish
   (`/var/lib/squeezebox/firstboot-done` appears; watch UART).
3. Restore your backups over serial console or SSH, then:

```sh
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf /root/.ssh/authorized_keys
/usr/lib/squeezebox/wifi.sh start
systemctl restart ssh
```

4. Re-verify: `cat /etc/os-release`, `systemctl is-system-running`,
   and the H1/H2/H12 rows of
   [docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md).

## Downgrade

Same procedure with the older image. Config formats are experimental
and may not be backward compatible — keep a version-labeled backup per
release and diff before restoring.

## Config compatibility notes

- `/etc/squeezebox/system.conf` keys (`WIFI_IF`, `WIFI_ENABLED`,
  `USEALSA_*`, `SDL_*`) are stable within 0.2.x; unknown keys are
  ignored by the shell-including scripts.
- `wpa_supplicant.conf` format is upstream wpa_supplicant syntax and
  carries across releases unchanged.
- SSH host keys regenerate if absent; restoring the old ones avoids
  host-key warnings on clients.
