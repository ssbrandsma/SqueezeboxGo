# Platform: RG35XX H (Allwinner H700)

Linux foundation for the Squeezebox firmware: pinned kernel + U-Boot + ATF,
device tree (in-tree chain + OOT display strategy), boot script, rootfs
skeleton, service integration, and reproducible SD image assembly.
Owner: Agent 1 (`platform/`, `build/image/`, `build/docker/`).

Boot flow: BROM -> SPL (sector 16) -> U-Boot FIT -> `boot.scr` -> `Image` +
`dtb.img` -> systemd -> splash -> wifi -> squeezeplay (Jive).

## Pinned sources (verified 2026-11-15)

| Component | Pin | SHA / hash | Role |
|---|---|---|---|
| linux (stable tree) | `v7.3.4` | `8310b43a…` tag; tarball sha256 `b11b6df8…` | kernel + H700 DTS |
| u-boot | `v2026.10` | commit `55084065…` | `anbernic_rg35xx_h700_defconfig` |
| ATF (BL31) | `v2.15.0` | commit `da738d5e…` | `PLAT=sun50i_h616` |
| container base | `debian:bookworm-slim` | `sha256:734a72b3…` | `build/docker/Dockerfile` |

Full pins + URLs: [`kernel/pins.env`](kernel/pins.env). Fetch:
`kernel/fetch.sh --fetch all` (verifies hashes/SHAs into `build/cache/`).

> Handoff for Lead: `docs/upstream-references/upstream-manifest.md` still shows
> `TBD (WP1)` for linux/u-boot — proposed replacements are `linux v7.3.4
> (8310b43a)` and `u-boot v2026.10 (55084065)`, plus new rows for ATF v2.15.0
> and the container digest above. (Not editing `docs/` — Lead-owned.)

## What is in-tree vs OOT (evidence, not assumption)

- In-tree @ v7.3.4: `sun50i-h700-anbernic-rg35xx-h.dts` -> `-plus.dts`
  (RTL8821CS Wi-Fi/BT) -> `-2024.dts` (gpio-keys, codec, regulators, USB).
  Sticks, buttons, AXP717, Wi-Fi/BT nodes, sun4i-codec + hp-detect: present.
- OOT gap: `sun50i-h616.dtsi` has **zero display nodes** (no DE/mixer, TCON,
  DSI, PWM) and the board chain has no panel nodes. The whole display pipeline
  + 640x480 RGB panel + PWM backlight is carried out-of-tree.
- Patch inventory + landing rules: [`kernel/patches/oot-patch-list.md`](kernel/patches/oot-patch-list.md);
  display template: [`device-tree/`](device-tree/). `series` is created with
  the first landed patch (WP2, hardware-gated).

## DRAM variants

Units ship with DDR3 or LPDDR4. `build-uboot.sh` builds both from one
defconfig (`ddr4` as-is; `ddr3` via `kernel/config/uboot-rg35xx-h-ddr3-fragment.conf`
switching to `SUNXI_DRAM_H616_DDR3_1333`). Images differ ONLY in the SPL blob
at sector 16. DDR3 TPR tuning + unit ID method are WP2 hardware gates.

## GPT layout (sunxi-aware)

Stock GPT collides with the BROM SPL load address (sector 16 vs array at
sectors 2-33), so [`build/image/mksunxi_gpt.py`](../../build/image/mksunxi_gpt.py)
writes the array at LBA 4096 (128 entries, fixed GUIDs). Verified: `sfdisk`
parses it and a 1.5 MB blob at sector 16 leaves it intact. Map:
[`build/image/partitions.txt`](../../build/image/partitions.txt).

## Rootfs + services

- `rootfs/`: `skeleton.list` + `overlay/etc` (fstab/hostname/os-release) +
  `mkrootfs.sh` (unprivileged staging, mtime clamping, sha256 manifest).
  Base userland (glibc/systemd/…) is a WP2 choice (debootstrap/buildroot);
  this tree layers on top idempotently. `/dev` is empty (devtmpfs).
- `services/`: systemd primary (`splash` -> `wifi` -> `squeezeplay`), logic in
  POSIX sh (busybox-init fallback documented in `services/README.md`).
  Jive launcher exports the interface-contracts env knobs and best-effort
  acquires `audio-owner`. Splash hook never blocks boot.
- `configuration/`: `system.conf` knobs, wpa_supplicant template (no PSKs in
  git), sshd drop-in (root key-only, no default passwords).

## Build (full chain; heavy steps run in the container)

```sh
build/docker/build.sh -- ./platform/rg35xx-h/kernel/fetch.sh --fetch all
# ... build-uboot.sh, build-kernel.sh, mkrootfs.sh, assemble-image.sh
# (exact commands: build/image/README.md)
```

## Validation status (WP1, no hardware, no docker on this host)

- Ran: GPT writer + `--check` + `sfdisk` cross-check + SPL-overlap proof;
  `mkrootfs.sh` full staging incl. reproducibility manifest; `fetch.sh`
  `--print-pins` + real ATF fetch w/ SHA check; `assemble-image.sh`
  `--check-deps`/`--dry-run`; `systemd-analyze verify` on all units;
  `bash -n` on every script; `mkfs.ext4 -d` unprivileged stage proof.
- Not run: full kernel/U-Boot compile (too heavy for WP1 by design), FAT stage
  + `boot.scr` build (needs container: `mkfs.vfat`, `mtools`, `mkimage`),
  `docker build`, any on-device boot. No shellcheck on host (in container).
