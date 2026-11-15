# Recovery — Squeezebox RG35XX H (0.2.0-exp2)

How to back up device state, get a non-booting unit back, and what
"failsafe" honestly means in this release: there is **no recovery
partition, no A/B slots, and no boot menu**. The failsafe is the UART
console plus re-flashing from a known-good image.

## What to back up

These paths hold everything not reproducible from the image.
Copy them to another machine over SSH (or serial console + copy/paste
for small files) before any re-flash:

| Path | Contents |
|---|---|
| `/etc/squeezebox/system.conf` | runtime knobs (`WIFI_*`, `USEALSA_*`, `SDL_*`) |
| `/etc/wpa_supplicant/wpa_supplicant.conf` | Wi-Fi credentials (mode 0600 — keep secret) |
| `/root/.ssh/authorized_keys` | your SSH login keys |
| `/etc/ssh/ssh_host_*` | host keys (avoid client warnings after restore) |
| `/var/lib/squeezebox/` | firstboot stamp + service state |

Whole-card backup (Linux host, card unmounted, replace `/dev/sdX`):

```sh
sudo dd if=/dev/sdX of=squeezebox-backup-$(date +%F).img bs=4M status=progress conv=fsync
```

Restore with the same `dd` flow as
[INSTALL.md](INSTALL.md#3-flash) (swap `if=`/`of=`). A backup image is
2 GiB; compress with `xz -6` for storage.

## If it does not boot

Work top-down; stop at the first step that recovers it.

1. **Wrong DRAM variant.** No SPL output on UART at all → re-flash the
   other variant (DDR4 first, then DDR3) and record the attempt. See
   [INSTALL.md](INSTALL.md#2-pick-ddr3-vs-ddr4).
2. **Bad flash / bad card.** Re-verify `sha256sum -c SHA256SUMS`,
   re-flash (Etcher validate: on), try another card.
3. **U-Boot console.** If SPL + U-Boot print but the kernel does not
   start, interrupt autoboot over UART and inspect the boot partition:

```text
fatls mmc 0:1
# expect: boot.scr  Image  dtb.img  (see build/image/partitions.txt)
```

Missing or zero-length files mean a truncated flash — re-flash. The
boot script source is
[platform/rg35xx-h/boot/boot.cmd](../platform/rg35xx-h/boot/boot.cmd);
`bootargs` pins `root=PARTUUID=0a1b2c3d-0002-...`.

4. **Mount the card on a Linux host.** The card is GPT with p1 FAT32
   (`SQUEEZEBOOT`) and p2 ext4 (`squeezebox-root`):

```sh
sudo mkdir -p /mnt/sqz-boot /mnt/sqz-root
sudo mount /dev/sdX1 /mnt/sqz-boot
sudo mount /dev/sdX2 /mnt/sqz-root
ls /mnt/sqz-boot                                # boot.scr Image dtb.img
cat /mnt/sqz-root/etc/os-release                 # confirm release
cat /mnt/sqz-root/var/lib/squeezebox/firstboot-done 2>/dev/null \
  || echo "first-boot never completed"
```

Fixes possible from here: replace a broken `system.conf` or
`wpa_supplicant.conf`, add an `authorized_keys`, inspect logs under
`/mnt/sqz-root/var/log/`. Unmount cleanly (`sudo umount` both) before
returning the card to the device.

5. **Re-flash.** The supported recovery for anything else
   (first-boot `dpkg --configure -a` failure, corrupted rootfs, lost
   SSH access with no console): restore from backup or flash the
   release image fresh per [INSTALL.md](INSTALL.md).

## If SSH is lost but the unit runs

SSH is root key-only with no password fallback
([platform/rg35xx-h/configuration/sshd-10-squeezebox.conf](../platform/rg35xx-h/configuration/sshd-10-squeezebox.conf)).
If your key stops working, use the serial console (115200 8N1,
`serial-getty@ttyS0.service`) to fix `/root/.ssh/authorized_keys`
(0600, `/root/.ssh` 0700) and `systemctl restart ssh`. Without UART
hardware, fall back to host-mounting the card (step 4 above).

## If Wi-Fi is lost but SSH over USB/Ethernet works

```sh
cat /etc/squeezebox/system.conf        # WIFI_ENABLED=1, WIFI_IF=wlan0
ls /etc/wpa_supplicant/wpa_supplicant.conf
/usr/lib/squeezebox/wifi.sh status
/usr/lib/squeezebox/wifi.sh stop; /usr/lib/squeezebox/wifi.sh start
dmesg | grep -i -E 'rtw|8821|mmc1|brcm'
```

`no such interface wlan0` means driver/firmware trouble — capture the
`dmesg` lines above and file against Agent 1 with the exact image
sha256 (triage table:
[docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md#5-failure-triage)).

## Data-loss warnings

- Re-flashing erases the whole card, including backups kept on it.
- Never store the only copy of `wpa_supplicant.conf` (cleartext PSK)
  or SSH keys in the repo, in result files, or on shared machines.
  Redact secrets from any log you attach
  (policy: [docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md#5-failure-triage)).
