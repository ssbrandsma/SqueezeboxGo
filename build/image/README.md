# Image assembly (RG35XX H)

Deterministic GPT SD images, one per DRAM variant (`ddr3`, `ddr4`). Unprivileged
build: filesystems are created in temp files and `dd`'d into place — no loop
mounts, no root. See `partitions.txt` for the exact LBA map.

## Layout (why not stock GPT?)

The Allwinner BROM loads the SPL from raw sector 16 (8 KiB), which overlaps a
stock GPT partition array (sectors 2-33). `mksunxi_gpt.py` writes a GPT whose
array lives at LBA 4096 (past the SPL+U-Boot blob at sectors 16..~3000):
`sfdisk`, the kernel, and U-Boot `part_efi` all parse it (verified). Variants
differ ONLY in the SPL blob at sector 16; partition bytes are identical.

## Build (inside the `build/docker` container)

```sh
platform/rg35xx-h/kernel/fetch.sh --fetch all --dir build/cache/upstream
platform/rg35xx-h/kernel/build-uboot.sh --uboot build/cache/upstream/u-boot-2026.10 \
    --atf build/cache/upstream/atf-2.15.0 --out build/cache/uboot
platform/rg35xx-h/kernel/build-kernel.sh --src build/cache/upstream/linux-7.3.4 \
    --out build/cache/kernel
# Base userland FIRST (unprivileged; postinst runs natively at first boot):
platform/rg35xx-h/rootfs/stage-userland.sh --staging build/cache/rootfs \
    --cache build/cache/userland-debs --epoch "$SOURCE_DATE_EPOCH"
platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch "$SOURCE_DATE_EPOCH"
build/image/stage-payload.sh --staging build/cache/rootfs \
    --core-tgz <squeezeplay-aarch64-*.tgz> --uibins <aarch64 bins> \
    --sdl2 <sdl2-kmsdrm prefix> --compat <sdl12-compat prefix> \
    --bsp-so <rg35xxh_bsp.so> --squeezeplay-src <sp>/src \
    --kernel-modules build/cache/kernel/modules \
    --target-libs <closure list> --epoch "$SOURCE_DATE_EPOCH"
build/image/assemble-image.sh --variant ddr4 --uboot build/cache/uboot \
    --kernel build/cache/kernel --rootfs build/cache/rootfs \
    --out releases/squeezebox-rg35xxh-ddr4.img
# repeat with --variant ddr3 for DDR3 units
```

Preflight without building: `assemble-image.sh --check-deps`, `--dry-run ...`.

## Base userland (stage-userland.sh)

Suite: trixie arm64 minbase + the `--include` set in
`platform/rg35xx-h/rootfs/userland-include.txt` (systemd/udev, ALSA,
wifi, ssh, kmod, firmware). trixie, not bookworm: the shipped payload
needs GLIBC_2.38, which bookworm's libc6 2.36 lacks (measured; see
`docs/test-results/wp2u-image.md`). The script runs unprivileged
(debootstrap `--foreign` under fakeroot + a rootless second stage that
unpacks every deb and synthesizes dpkg's `status` as "unpacked");
`dpkg --configure -a` + `ssh-keygen -A` run natively at first boot via
`squeezebox-firstboot.service`. Docker hosts can print/run the privileged
equivalent instead: `stage-userland.sh --userland container`.

## Reproducibility

Fixed disk GUID + PARTUUIDs + fs UUIDs + FAT volid-from-epoch, `mkfs.ext4`
under `fakeroot` with `lazy_itable_init=0`, all staging mtimes = epoch,
per-image `.sha256`.

Byte-repro status (WP2, measured 2026-11-15, see
`docs/test-results/wp2-platform.md`): with `mke2fs >= 1.47.1` +
`SOURCE_DATE_EPOCH` (1.47.1 clamps fs stamps and all `-d` inode times) +
`-E hash_seed=` (pinned in `assemble-image.sh`, works on every mke2fs),
double builds are byte-identical (0 differing bytes, journal UUID is stable).
With stock `mke2fs 1.47.0` the fs wrapper still varies (~340 bytes:
`s_mkfs_time`/`s_wtime`/`s_lastcheck`, inode atime/ctime, checksums) and the
script warns; staging content is byte-identical either way. `libfaketime`
was measured and rejected: it double-shifts the already-clamped `-d` source
times (392 diff bytes, worse than baseline). Container TODO: e2fsprogs
>= 1.47.1 in `build/docker` (bookworm ships 1.46.x). FAT side: `mtools`
timestamps follow file mtimes (already clamped); verify with diffoscope.

## Flashing (human step, never automated here)

```sh
sha256sum -c squeezebox-rg35xxh-<variant>.img.sha256
sudo dd if=squeezebox-rg35xxh-<variant>.img of=/dev/<YOUR_SD> bs=4M status=progress conv=fsync
```

Pick the variant matching the unit's DRAM (ID method TBD on hardware).
