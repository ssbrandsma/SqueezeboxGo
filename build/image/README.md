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
platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch "$SOURCE_DATE_EPOCH"
build/image/assemble-image.sh --variant ddr4 --uboot build/cache/uboot \
    --kernel build/cache/kernel --rootfs build/cache/rootfs \
    --out releases/squeezebox-rg35xxh-ddr4.img
# repeat with --variant ddr3 for DDR3 units
```

Preflight without building: `assemble-image.sh --check-deps`, `--dry-run ...`.

## Reproducibility

Fixed disk GUID + PARTUUIDs + fs UUIDs + FAT volid-from-epoch, `mkfs.ext4`
under `fakeroot` with `lazy_itable_init=0`, all staging mtimes = epoch,
per-image `.sha256`.

Known gap (WP1, measured): stock `mke2fs 1.47.0` embeds wall-clock
`s_mkfs_time`/`s_wtime`/`s_lastcheck` (ignores `SOURCE_DATE_EPOCH`) and a
random journal UUID — double builds differ in 349 superblock/journal bytes
(verified 2026-11-15). Staging content is byte-identical; only the fs wrapper
varies. Fix path (WP2, with Agent 6's rebuild-twice gate): newer e2fsprogs
(>=1.47.1 honors `SOURCE_DATE_EPOCH`) or `libfaketime` in the container +
pinned journal UUID. FAT side: `mtools` timestamps follow file mtimes
(already clamped); verify with diffoscope.

## Flashing (human step, never automated here)

```sh
sha256sum -c squeezebox-rg35xxh-<variant>.img.sha256
sudo dd if=squeezebox-rg35xxh-<variant>.img of=/dev/<YOUR_SD> bs=4M status=progress conv=fsync
```

Pick the variant matching the unit's DRAM (ID method TBD on hardware).
