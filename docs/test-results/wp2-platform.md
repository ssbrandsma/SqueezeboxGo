# WP2 platform test results (first-boot integration)

Date: 2026-11-15. Branch: `wp2/platform`. Base: `main @ 96217b5`.
Host: Ubuntu 24.04 x86_64, 12 cores. No docker daemon, no root: all builds
ran under a rootless sysroot (`/tmp/wp2sys`, Ubuntu noble .debs extracted
with `dpkg-deb -x`) with `PATH/LD_LIBRARY_PATH/CPATH/LIBRARY_PATH` overrides
plus `BISON_PKGDATADIR`, `M4`, `SWIG_LIB`.

Toolchain: `gcc-aarch64-linux-gnu 13.3.0`, binutils 2.42, bison 3.8.2,
flex 2.6.4, swig 4.0, dtc 1.7.0, mkimage 2025.10 (sysroot) cross-checked
against tree-built mkimage from u-boot-2026.10 (byte-identical script
output), mtools 4.0.43, dosfstools 4.2, `mke2fs 1.47.0`, fakeroot.
`SOURCE_DATE_EPOCH=1794334272` throughout.

Full logs: `/tmp/wp2-logs/` on the build host
(`uboot-ddr4.log` 831 lines, `uboot-ddr3.log` 844, `kernel.log` 18343,
`assemble-ddr4.log`, `assemble-ddr3.log`). Sources + staging under
`build/cache/` (gitignored). Images in `/tmp` (NOT in git).

## 1. Fetch (`fetch.sh --fetch all`)

```
linux  v7.3.4 8310b43a724c54668eeaa6860234078a7886915a
  tarball sha256 b11b6df8295e8e991ff040b71aaa4994a8b55caa23b6b092907f195b5840fd1f  OK
u-boot v2026.10 HEAD 5508406582f6f7120dce0c4b3059819a41788db2  OK
atf    v2.15.0 HEAD da738d5eae93af342fdc4995dd3c05acb4c9d757  OK
in-tree RG35XX DTS chain present (rg35xx-h/-plus/-2024.dts)
sizes: linux-7.3.4 1.8G, tarball 155M, u-boot-2026.10 418M, atf-2.15.0 76M
```

## 2. ATF + U-Boot (`build-uboot.sh`, both variants)

`--uboot build/cache/upstream/u-boot-2026.10 --atf .../atf-2.15.0
--out build/cache/uboot --variant ddr4|ddr3 --jobs 12` — exit 0 both.

```
ddr4/bl31.bin                  41060  d71deea5fc861c12ff80d0b665120c45ec20c697bc39689a48b582d0c5044a36
ddr4/u-boot-sunxi-with-spl.bin 758281 edfcbce254db2cea6c3497aab8cd7e50ad65651e2fd21dbf27f82ea9c28fb8d8
ddr4/u-boot.itb                716297 792faf8445187beba005cc7245645f0b78af0d08d64aa30e9bbeb3265bc0c906
ddr3/bl31.bin                  41060  d71deea5 (same: shared BL31 build)
ddr3/u-boot-sunxi-with-spl.bin 758281 33bd339b749801a3df60822eca42543c538b8a2b9dd7d85c0d8a8138a0666752
ddr3/u-boot.itb                716297 792faf84 (same: no DRAM code in FIT)
```

Checks: `obj-ddr3/.config` has `SUNXI_DRAM_H616_DDR3_1333=y` +
`LPDDR4 is not set`; ddr4 inverse. SPL blobs differ in 24793 bytes
(same size; DRAM init + eGON checksum). `u-boot.itb` stages from
`u-boot-sunxi-with-spl.fit.itb` (real 2026.10 name, see fixes).
Kconfig `override: reassigning` warnings on the ddr3 fragment are benign.

## 3. Kernel (`build-kernel.sh --jobs 12`) — exit 0, no errors

```
boot/Image  53901824  cd6e92fbea7228b70e15c6f61025d0b1dd122293c2a22ec7729d02ca67ff96ec
  file: Linux kernel ARM64 boot executable Image, little-endian, 4K pages
dtbs/sun50i-h700-anbernic-rg35xx-h.dtb  28301
  b8b0bfa32b93c3811df7cd168f46f220c3d7ea9723eeb94d3dd5e77f819f5412
modules: 1676 .ko, 379M under modules/lib/modules/7.3.4
```

Fragment verified in `.config`: `SND_SUN8I_CODEC=y`, `RTW88_8821CS=m`,
`DRM_SUN4I=y`, `EXT4_FS=y`, `VFAT_FS=y`, `MMC_SUNXI=y`. DTB decompiles to
`model = "Anbernic RG35XX H"` (38 gpio-keys/codec/mmc/axp nodes). The 12
log lines matching `error` are object filenames (`scsi_error.o`, …).

## 4. Rootfs (`mkrootfs.sh --with-services --with-config --epoch …`)

Exit 0: 14 files, 54 mode entries; services executable + 3 unit symlinks;
all mtimes (incl. manifests after fix) `2026-11-10 19:11:12 +0100` (epoch).

## 5. FAT / boot.scr stages

- `boot.scr` (mkimage, SDE): 849 bytes, `u-boot legacy uImage,
  Linux/ARM 64-bit Script`, timestamp = epoch; double build byte-identical.
- Payload = 8-byte multi-image length header (`0309`=777, `0`) + verbatim
  `boot.cmd` (777 B); roundtrip `cmp` OK after skipping 72 bytes.
  `image_locate_script` (u-boot `boot/image-board.c`) seeks past the length
  words (`while (*data++);`), so the format is correct for `source`.
- Fresh `mkfs.vfat` differs run-to-run in 2 bytes (volume-label entry
  ctime/wtime — dosfstools has no SDE support); `mcopy` honors SDE
  (no diffs). Fixed with `build/image/clamp-fat.py` + `TZ=UTC0`:
  double FAT build now byte-identical, `fsck.vfat` clean, label/volid kept.

## 6. Images (`assemble-image.sh`, 2048 MiB, `--out /tmp/…`)

```
squeezebox-rg35xxh-ddr4.img  2147483648  467794f1a0d36fa7f83e61138adb5aede713af7ddf50156c6f852d2d53e7e06d
squeezebox-rg35xxh-ddr3.img  2147483648  ca9287d33eba52ed56e33e61c1be6199406e5e25981072be8b4db436f874751b
```

Validation (ddr4; ddr3 identical except SPL):
- `sfdisk -d` parses: protective MBR `0xEE`, disk `0A1B2C3D-0000-…`,
  p1 BOOT 32768..557055 EFI-System `…-0001-…`, p2 ROOTFS 557056..4194271
  Linux `…-0002-…` (matches `boot.cmd` `root=PARTUUID=`), first-lba 4128.
- `file`: `DOS/MBR boot sector; partition 1: ID=0xee …`.
- SPL: 1482 sectors at LBA 16 (ends 1498 < 4096 ✓); first 758281 bytes
  `cmp`-equal to staging, 503-byte pad all zero.
- FAT (`mdir`): `SQUEEZEBOOT`, serial `6AF3-5E40` (epoch volid), `boot.scr`
  849 + `Image` 53901824 + `dtb.img` 28301, all dated epoch UTC;
  extracted `Image`/`dtb.img` SHAs match kernel staging; `fsck.vfat` clean.
- ext4: UUID `0a1b2c3d-…-0001`, label `squeezebox-root`, hash seed pinned
  `…-0002`, dirs epoch-dated, `e2fsck -f` clean (`67 files, 16729 blocks`).

Reproducibility (measured):
- Cross-variant: 25164 diff bytes = 24793 SPL region + 371 ext4 wrapper,
  0 elsewhere (GPT/FAT/SPL-placement identical).
- Double ddr4 build: 464 diff bytes, ALL inside p2; per-file `debugfs
  dump` of all 15 payloads identical; offsets = 414 group-0
  superblock/inode-table + 50 backup-superblock/GDT copies — i.e. only
  1.47.0 timestamps/checksums (see §7). GPT+SPL+FAT bit-identical.
- ext4 recipe proof (64M test fs, Ubuntu-signed questing `mke2fs 1.47.2`):
  `1.47.2 + SDE + hash_seed` → **0 diff bytes**; without `hash_seed` → 16
  (seed only); without SDE → 74. Baseline `1.47.0`: 340
  (23 superblock + 317 inode table). `libfaketime` REJECTED: 392 diffs —
  it shifts the already-clamped `-d` source times a second time
  (dirs landed on 2026-11-05 instead of the epoch).

## 7. Fixes landed on this branch

- `build-kernel.sh` / `build-uboot.sh`: absolutize `--src/--out/--uboot/
  --atf` (`realpath -m`) — `make -C` resolved relative `O=` and
  `INSTALL_MOD_PATH=` inside the source tree (observed stray objdir).
- `build-uboot.sh`: accept `u-boot-sunxi-with-spl.fit.itb` as the FIT
  source (real 2026.10 name; staged as `u-boot.itb`); silence
  single-variant `find` stderr in the checksum step.
- `mkrootfs.sh`: pin `manifest.*` mtimes to the epoch (were wall-clock).
- `assemble-image.sh`: `-E hash_seed=<fixed>` (works on every mke2fs);
  warn when `mke2fs < 1.47.1`; `TZ=UTC0`; call `clamp-fat.py` (new) after
  `mkfs.vfat`; dry-run plan updated.
- `build/image/README.md`: byte-repro section rewritten with measurements;
  `build/docker/Dockerfile`: corrected libfaketime comment + e2fsprogs
  ≥1.47.1 TODO (bookworm ships 1.46.x).

## 8. QA checklist

| Check | Result |
|---|---|
| Kernel cross-build (Image + RG35XX-H DTB) | PASS (exit 0, §3) |
| U-Boot DDR3+DDR4 (SPL + u-boot.itb) | PASS (exit 0, §2) |
| mkrootfs + FAT/boot.scr stages | PASS (§4, §5) |
| assemble-image both variants to /tmp | PASS (§6) |
| sfdisk/file/SPL/FAT/rootfs validation | PASS (§6) |
| ext4 byte-repro fix | PASS with gate: 0-diff recipe proven; full-image repro needs container e2fsprogs ≥ 1.47.1 (TODO, script warns) |
| Physical boot on RG35XX H | NOT RUN (no hardware; DDR3 TPR + panel still HW-gated per WP1) |
