# Install — Squeezebox RG35XX H (0.2.0-exp2)

Flash a release image to microSD, boot the handheld, and get on the
network. Read [KNOWN_ISSUES.md](KNOWN_ISSUES.md) first: this is an
experimental release and the display stays dark without the pending
panel driver — plan for UART/serial access.

## What you need

- Anbernic RG35XX H (H700) handheld.
- microSD card, >= 4 GB (the image is 2 GiB), plus a card reader.
- USB-C cable; 3.5 mm headphones (for audio tests).
- Recommended: a 3.3 V TTL USB-UART adapter for the debug header
  (see [UART access](#uart-access) and [docs/hardware.md](hardware.md)).

## 1. Download and verify

A release dir holds the compressed images plus `MANIFEST.json` and
`SHA256SUMS` (layout: [releases/README.md](../releases/README.md)).
For 0.2.0-exp2 the artifacts are recorded in
[releases/MANIFEST.json](../releases/MANIFEST.json):

- `squeezebox-rg35xxh-ddr3.img.xz` (~164 MB, expands to 2 GiB)
- `squeezebox-rg35xxh-ddr4.img.xz` (~164 MB, expands to 2 GiB)

Verify before flashing (Linux):

```sh
sha256sum -c SHA256SUMS
# or:
bash releases/checksum.sh verify <release-dir>
```

All lines must print `OK`. Optionally confirm the image itself passes
the host gate (needs the repo + Python 3):

```sh
xz -d -k squeezebox-rg35xxh-<variant>.img.xz
python3 tests/check_image.py squeezebox-rg35xxh-<variant>.img
# must print PASS (see docs/test-results/HW_TEST_PLAN.md preconditions)
```

## 2. Pick DDR3 vs DDR4

Units shipped with either DRAM type and there is no software ID method
yet. The two images differ **only** in the SPL blob (DRAM timings) at
raw sector 16; partitions are identical
(see [build/image/partitions.txt](../build/image/partitions.txt)).

- If you know your unit's DRAM, flash the matching image.
- If unsure: flash **DDR4 first**. No SPL output on UART means wrong
  variant (or a bad flash) — re-flash with the other one and record
  which booted.

## 3. Flash

Flashing writes a whole disk. **Triple-check the target drive**; never
flash the host OS drive. Pick one tool:

- [balenaEtcher](https://etcher.balena.io/) — Validate write: on.
- [Rufus](https://rufus.ie/) — **DD mode**, not ISO mode.
- Linux `dd` (replace `/dev/sdX` with the card device, not a partition):

```sh
xz -dc squeezebox-rg35xxh-<variant>.img.xz | \
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Eject safely, insert the card into the RG35XX H (lower slot if two).

## 4. First boot

Power on. First boot runs finalization on the device
([platform/rg35xx-h/services/firstboot.sh](../platform/rg35xx-h/services/firstboot.sh),
ordered by `squeezebox-firstboot.service`): native `dpkg --configure -a`
over the 141 unpacked userland packages, then `ssh-keygen -A` for host
keys. This takes minutes and is **device-unproven** — watch the UART log
and be patient. Completion is stamped at
`/var/lib/squeezebox/firstboot-done`; later boots skip it.

Expected UART sequence: Allwinner BROM → SPL banner →
`U-Boot 2026.10 ... DRAM: 1024 MiB` → `boot.scr` → kernel
(`Linux version ...`) → splash → SqueezePlay UI (target: UI within
90 s, matrix H1 in [docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md)).

Confirm the release on the device:

```sh
cat /etc/os-release   # PRETTY_NAME="Squeezebox RG35XX H (0.2.0-exp2)"
```

## 5. UART access

1. Verify the header pinout and voltage (**3.3 V TTL assumed** — confirm
   at the steward-fu RG35XX H UART reference) before connecting. Never
   feed 5 V or RS-232 levels into the header.
2. Connect GND/RX/TX, open 115200 8N1 with capture:

```sh
picocom -b 115200 /dev/ttyUSB0 -l
# or: PuTTY serial + session logging to file
```

The kernel console is `ttyS0,115200n8`
([platform/rg35xx-h/boot/boot.cmd](../platform/rg35xx-h/boot/boot.cmd))
and a serial getty is enabled (`serial-getty@ttyS0.service`).

## 6. SSH access

SSH is **root, key-only, no default passwords**
([platform/rg35xx-h/configuration/sshd-10-squeezebox.conf](../platform/rg35xx-h/configuration/sshd-10-squeezebox.conf)).
Host keys are generated at first boot. No USB-stick or web key
provisioning exists yet, so add your key over the serial console:

```sh
mkdir -p /root/.ssh && chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys   # paste your id_ed25519.pub, then Ctrl-D
chmod 600 /root/.ssh/authorized_keys
```

Then, with the unit's IP (UI network screen or router DHCP lease):

```sh
ssh root@<ip>
uname -a; cat /etc/os-release; systemctl is-system-running
```

## 7. Wi-Fi setup

Radio: RTL8821CS on `wlan0` (see [docs/hardware.md](hardware.md)).
Bring-up is `wpa_supplicant` + `udhcpc`, driven by
`/usr/lib/squeezebox/wifi.sh` (`start|stop|status`) and configured in
`/etc/squeezebox/system.conf` (`WIFI_IF`, `WIFI_ENABLED`).

1. From the template (never commit a filled-in copy — it holds a PSK):

```sh
cp /etc/squeezebox/wpa_supplicant.conf.template /etc/wpa_supplicant/wpa_supplicant.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
```

2. Generate a PSK (avoids storing the cleartext passphrase) and edit
   the `ssid=` / `psk=` lines into the new file:

```sh
wpa_passphrase YOUR_SSID 'your passphrase'
```

3. Start and verify:

```sh
/usr/lib/squeezebox/wifi.sh start
/usr/lib/squeezebox/wifi.sh status
ping -c3 <gateway>
```

The template source in the repo is
[platform/rg35xx-h/configuration/wpa_supplicant.conf.template](../platform/rg35xx-h/configuration/wpa_supplicant.conf.template).

## 8. Hardware tests

Run the matrix H1–H18 in
[docs/test-results/HW_TEST_PLAN.md](test-results/HW_TEST_PLAN.md) and
record results in `docs/test-results/` as a new `hw-<date>-<variant>.md`
(you create this file). Attach the
UART boot log and the SSH capture (`uname/dmesg/journal/os-release`).
Never paste passwords, tokens, or AP keys into result files.
