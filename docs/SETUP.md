# Setup — dev environment, device SSH, iteration loop

From zero to editing SqueezeboxGo and testing on hardware.

## 1. Host

- Ubuntu 24.04 (native or WSL2), on the Linux filesystem (not `/mnt/c`).
- Base tools: `sudo apt install git curl python3 unzip sha256sum xz-utils patch file readelf qemu-user shellcheck lua5.1`.
- Cross toolchain (for §1 builds in [BUILD-SQUEEZEBOXGO.md](BUILD-SQUEEZEBOXGO.md)):
  `sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu`.
- Clone and sanity-check:

```sh
git clone https://github.com/ssbrandsma/SqueezeboxGo.git
cd SqueezeboxGo
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
bash tests/selftest.sh
```

No Docker needed for the SqueezeboxGo app path (containers exist only
for the mainline firmware track).

## 2. Device SSH (one time)

The RG35XX H runs stock Ubuntu 22.04 with OpenSSH. Bring it onto your
LAN (stock UI: Wi-Fi settings), find its IP on the device (Settings →
Network, or your router's DHCP list), then from the host:

```sh
# key auth (recommended; the stock image accepts ~/.ssh/authorized_keys)
ssh-copy-id <user>@<device-ip>
# sudo must be passwordless for the dev user (visudo on device):
#   <user> ALL=(ALL) NOPASSWD:ALL
```

Recommended `~/.ssh/config` alias (used by every command in this repo's
docs — adjust host/user/key to taste):

```text
Host rg35xxh
    HostName <device-ip>
    User <user>
    IdentityFile ~/.ssh/<your-key>
    ServerAliveInterval 30
```

Verify:

```sh
ssh rg35xxh 'whoami; sudo -n whoami; uname -a; cat /sys/firmware/devicetree/base/model 2>/dev/null'
```

Notes:

- Never commit the alias user/key/IP, passwords, or private keys.
  Docs use `<placeholders>`; logs must be scrubbed before filing.
- Stock auto-suspends after ~80 s idle (dmenu timer) — SSH stalls, not
  drops. Keep the device awake while working (input) or run
  long commands with `nohup` + output to a file.
- UART (`ttyS0`, 115200 8N1) is the recovery channel; see
  [RECOVERY.md](RECOVERY.md). Prefer SSH for routine work.

## 3. Deploy + iterate

First deploy (full path — build inputs per
[BUILD-SQUEEZEBOXGO.md](BUILD-SQUEEZEBOXGO.md) §1–3, or grab a release
ZIP and skip to the `scp`):

```sh
squeezebox-go/pack.sh --output /tmp/sbgo-dist
scp /tmp/sbgo-dist/SqueezeboxGo-*.zip rg35xxh:/tmp/sbgo.zip
ssh rg35xxh 'sudo -n unzip -o -q /tmp/sbgo.zip -d /mnt/mmc/Roms/ \
  && cat /mnt/mmc/Roms/APPS/SqueezeboxGo/VERSION'
# handheld: App Center -> SqueezeboxGo
```

Fast loop for entry/launcher/applet/Lua edits (no repack):

```sh
scp squeezebox-go/runtime/launch.sh rg35xxh:/tmp/launch.sh
ssh rg35xxh 'sudo -n cp /tmp/launch.sh /opt/squeezebox-go/launch.sh'
# handheld: quit (Return to Anbernic) and relaunch from App Center
```

Full pack for `jive/` trees, skins, `VERSION` bumps, or anything the
entry's hash check must see. The entry auto-upgrades on version
change and preserves `/opt/squeezebox-go/config/` (settings, seeds,
installed applets).

## 4. Device cheat-sheet

| Need | Where / how |
|---|---|
| Launch log | `/dev/shm/squeezebox-go/logs/launch-*.log` |
| Jive log | `/dev/shm/squeezebox-go/logs/jive.log` |
| Install log | `/opt/squeezebox-go/install.log` |
| Jive home (settings, applets) | `/opt/squeezebox-go/config/jive-home/` |
| Framebuffer | `/dev/fb0` (mode: `/sys/class/graphics/fb0/{mode,virtual_size,bits_per_pixel}`) |
| Audio | `plughw:CARD=audiocodec,DEV=0`; holder: `cat /proc/asound/card0/pcm0p/sub0/status` |
| Input nodes | `/dev/input/event*` (`ANBERNIC-keys`); mapper: `pgrep -af evdev2jive` |
| Frontend unit | `systemctl status launcher.service` (stop only, never disable) |
| Hardware-test lock | `/tmp/sb-hw-test.lock` — one writer at a time |

Safety (non-negotiable): never reflash/repartition a card from
scripts; never touch bootloader, kernel, PMIC voltages, or `dmenu.bin`;
`systemctl stop` (never disable/mask) for the frontend; a reboot must
always restore stock. Details: [stock/README.md](../stock/README.md).

## 5. Gates before every push

```sh
bash tests/selftest.sh
bash squeezebox-go/tests/test-package.sh
bash stock/tests/test-rg35xxh-identity.sh
bash stock/tests/test-sysv-shim.sh
bash ui/input/tests/run_tests.sh
bash tests/run_shellcheck.sh
```

New behavior ships with a test in the matching suite. Keep generated
firmware images, build caches, secrets, and large dependencies out of
git (see `.gitignore`; the two device-built compat binaries are the
documented exception).
