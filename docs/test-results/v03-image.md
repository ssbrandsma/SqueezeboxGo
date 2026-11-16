# 0.3.0-exp3 image rebuild — test results

Date: 2026-11-16. Branch: `v03/image`. Base: `main @ 200c6e1`
(LED scheme committed). Host: Ubuntu 24.04 x86_64, 12 cores, no root,
no docker: rootless sysroot (`/tmp/wp2sys` + `/tmp/sqz-userland/host-tools`,
proven WP2 env) with `PATH/LD_LIBRARY_PATH/CPATH/LIBRARY_PATH` overrides
plus `BISON_PKGDATADIR`, `M4`, `SWIG_LIB`, host python3 (setuptools).
`SOURCE_DATE_EPOCH=1794823250` (base HEAD time) throughout.

Owner note: written by the 0.3.0 rebuild integrator on Workflow task
instruction; `docs/test-results/` is Agent 6's tree — code fixes are on
this branch, flagged for owner review (see §8).

## Summary

First image WITH the OOT panel pipeline (series 0001-0005) + LED scheme
(0006 heartbeat, CMD_GPIO, led.sh): kernel Image + RG35XX-H DTB rebuilt
from the full 6-patch series, U-Boot rebuilt with the common GPIO
fragment on both variants, userland + payload restaged through the real
scripts (proven 0.2.0 procedure), both 2 GiB `.img` assembled at the
exact required paths.

| Check | Status | Notes |
|---|---|---|
| fetch:pins | PASS | linux tarball sha OK, u-boot/atf HEAD == pins |
| kernel:series | PASS | 0001-0006 apply, Image+modules+dtbs exit 0 |
| kernel:dtb-led | PASS | `linux,default-trigger = "heartbeat"` in DTB |
| kernel:dtb-panel | PASS | panel/backlight/DE33/mixer/TCON nodes in DTB |
| uboot:gpio | PASS | CONFIG_CMD_GPIO=y both; help text in both blobs |
| uboot:variants | PASS | DDR3_1333 vs LPDDR4 correct; shared BL31 |
| userland:stage | PASS | 141 pkgs, Release-sig verified, 299M |
| rootfs:led | PASS | led.sh 0755 in staging AND in-image ext4 |
| boot:scr | PASS | boot.scr contains `gpio set 267` (both images) |
| payload:restage | PASS | 11837 files, 6 libs kept from userland |
| smoke:jive | PASS | main loop (RC=124), 0 errors, staged loader |
| image:ddr3+ddr4 | PASS | both exit 0 at exact /tmp/sqz-v03 paths |
| image:gate | PASS | check_image PASS both, no-secrets clean |
| image:bytes | PASS | FAT SHAs == staging; SPL == staging + zero pad |
| image:cross | PASS | 24793 pre-rootfs diffs (== 0.2.0 SPL count) |
| suite:selftest | PASS | 27/27; led tests 11/11; shellcheck clean |
| boot:target | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 16, NOT RUN: 1.

## 1. Fetch + kernel (series 0001-0006)

```
$ ./platform/rg35xx-h/kernel/fetch.sh --fetch all --dir build/cache/upstream
linux  v7.3.4 tarball sha256 b11b6df8... OK (extracted 1.8G)
u-boot v2026.10 HEAD 5508406582f6f7120dce0c4b3059819a41788db2 OK
atf    v2.15.0 HEAD da738d5eae93af342fdc4995dd3c05acb4c9d757 OK
$ ./platform/rg35xx-h/kernel/build-kernel.sh --src ... --out build/cache/kernel --jobs 12
applying 0001..0006 (all "patching file", no fuzz, no .rej)
KERNEL_EXIT=0
boot/Image  53901824  0ba7afe5c2a90f0e5e6e885cb8ad84d182449c28605e68288af555429523dd24
dtbs/...-rg35xx-h.dtb  32473  fc345c3fa0d56ecf33a0996d8123cab34077c955820c5614876f9a84e27bb087
modules: 1675 .ko under modules/lib/modules/7.3.4
```

DTB evidence (`dtc -I dtb -O dts`, `model = "Anbernic RG35XX H"`):

- LED: `linux,default-trigger = "heartbeat"` on the PI11 status LED (0006).
- Panel: `panel@0 { compatible = "anbernic,rg35xx-plus-panel" }`
  (in-tree nv3052c match) + `pwm-backlight` + `regulator-gpio-lcd-vdd`.
- Pipeline: `sun50i-h616-de33`, `de33-mixer-0`, `tcon-top@6510000`,
  `sun8i-r40-tcon-lcd`, `pwm-backlight` all present in strings/fdtdump.
- DTB grew 28301 (0.2.0, no OOT) -> 32473 bytes (display + LED nodes).

## 2. U-Boot (common fragment on both variants)

```
$ ./platform/rg35xx-h/kernel/build-uboot.sh --uboot ... --atf ... \
    --out build/cache/uboot --variant both --jobs 12   # exit 0
ddr4/bl31.bin                  41060  00935eea...ece0
ddr4/u-boot-sunxi-with-spl.bin 758281 f91e3653...680f
ddr4/u-boot.itb                716297 5c3dd8ae...5c2f
ddr3/bl31.bin                  41060  00935eea (same: shared BL31)
ddr3/u-boot-sunxi-with-spl.bin 758281 31927ec7...f1d
ddr3/u-boot.itb                716297 5c3dd8ae (same: no DRAM code in FIT)
```

- `obj-ddr4/.config`: `SUNXI_DRAM_H616_LPDDR4=y` + `CONFIG_CMD_GPIO=y`.
- `obj-ddr3/.config`: `SUNXI_DRAM_H616_DDR3_1333=y`,
  `LPDDR4 is not set` + `CONFIG_CMD_GPIO=y`.
- `strings` on all four staged blobs finds the gpio command help text
  `query and control gpio pins` (v2026.10 wording of cmd/gpio.c; the
  task's example string `gpio - query and control` is older U-Boot
  wording — same command, verified at the source `U_BOOT_CMD(gpio,…)`).

## 3. Userland + rootfs (proven 0.2.0 procedure)

```
$ ./platform/rg35xx-h/rootfs/stage-userland.sh --staging build/cache/rootfs \
    --cache build/cache/userland-debs --epoch 1794823250
release-verify: ok(keyring=.../.userland-keyring/debian-archive-trixie-keyring.gpg)
dpkg status: 141 packages unpacked (18 users, all locked)
userland ready (141 packages, 299M)
$ ./platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch 1794823250
base userland present; serial-getty@ttyS0/getty@tty1/ssh/timesyncd enabled
staging ready (7170 files)
```

- `usr/lib/squeezebox/led.sh` staged executable (0755), in manifest.
- `etc/os-release`: `VERSION_ID=0.3.0-exp3`.
- One script bug found by this run and fixed on the branch: relative
  `--staging`/`--cache` broke the provenance redirect + debootstrap
  (see §8); rerun after the fix is the recorded staging.

## 4. Payload + smoke

```
$ ./build/image/stage-payload.sh --staging build/cache/rootfs \
    --core-tgz .../squeezeplay-aarch64-9.0.0.tgz (sha ecdb8d8e…, == 0.2.0 record)
    --uibins ... --sdl2 .../sdl2-kmsdrm --compat .../sdl12-compat ... \
    --kernel-modules build/cache/kernel/modules --target-libs ... --epoch ...
payload ready (11837 files; 6 SONAMEs kept from userland, as 0.2.0)
```

File delta vs 0.2.0's 11834: +1 led.sh (mkrootfs) +2 kernel-module set
churn (display-class modules from the OOT-enabled build).

```
$ qemu-aarch64 -L $R ... jive   # SDL dummy, 60 s timeout
JIVE_RC=124 (alive at timeout = main loop)
0 FATAL/GLIBC/symbol errors; rg35xxh_bsp applet loads
libm/libc/SDL resolve into STAGED userland (host has no aarch64 libs)
```

## 5. Images + verification

```
$ ./build/image/assemble-image.sh --variant ddr4 ... --out /tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img  # exit 0
$ ./build/image/assemble-image.sh --variant ddr3 ... --out /tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img  # exit 0
/tmp/sqz-v03/squeezebox-rg35xxh-ddr3.img  2147483648
  82fd269a3baceeda5359c23f5b644383ed59755ba7652af85633f13c9730cb9d
/tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img  2147483648
  6c3247629b4e9d1973a8622b308cbc2aff9444af4376b44581637e334a326173
```

(`.sha256` sidecars next to each image, written by the assembler.)

- `tests/check_image.py` both: `[RESULT] image: PASS`,
  `checked 2 target(s), 0 problem(s)`, no-secrets scan clean.
- FAT extract (mcopy): `boot.scr` identical both variants
  (`3535ef2b…`), contains `gpio set 267`; `Image` SHA == kernel
  staging (`0ba7afe5…`); `dtb.img` SHA == staging (`fc345c3f…`).
- SPL: in-image sectors 16..1497 byte-equal staging blobs, 503-byte
  zero pad both variants; e2fsck -f clean; debugfs shows led.sh 0755,
  os-release 0.3.0-exp3, `lib/modules/7.3.4`.
- Cross-variant: 24793 pre-rootfs diff bytes == 0.2.0's exact SPL
  count (proves rootfs/FAT/GPT identical apart from SPL); rest is the
  mke2fs-1.47.0 ext4 wrapper (assembler warns as designed).

## 6. Suites

- `tests/selftest.sh`: 27/27 PASS.
- `services/tests/test-led.sh`: 11/11 PASS.
- `shellcheck -S warning` on the touched script: clean.

## 7. How to reproduce

```sh
git checkout v03/image
. /tmp/sqz-v03/env.sh   # host-only: wp2sys + host-tools PATH/CPATH/etc (NOT committed)
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
platform/rg35xx-h/kernel/fetch.sh --fetch all --dir build/cache/upstream
platform/rg35xx-h/kernel/build-uboot.sh --uboot build/cache/upstream/u-boot-2026.10 \
  --atf build/cache/upstream/atf-2.15.0 --out build/cache/uboot --variant both --jobs 12
platform/rg35xx-h/kernel/build-kernel.sh --src build/cache/upstream/linux-7.3.4 \
  --out build/cache/kernel --jobs 12
platform/rg35xx-h/rootfs/stage-userland.sh --staging build/cache/rootfs \
  --cache build/cache/userland-debs --epoch "$SOURCE_DATE_EPOCH"
platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
  --with-services --with-config --epoch "$SOURCE_DATE_EPOCH"
build/image/stage-payload.sh --staging build/cache/rootfs [...] \
  --kernel-modules build/cache/kernel/modules --epoch "$SOURCE_DATE_EPOCH"
build/image/assemble-image.sh --variant ddr4 ... --out /tmp/sqz-v03/squeezebox-rg35xxh-ddr4.img  # + ddr3
python3 tests/check_image.py /tmp/sqz-v03/*.img
```

Payload inputs reused from verified 0.1.0/0.2.0 host artifacts
(core tarball `ecdb8d8e…`, uibins aarch64 ELFs, sdl2-kmsdrm +
sdl12-compat prefixes, DejaVu `sp-pristine/src`, 19/19 closure
hostpaths present); kernel modules + DTB + U-Boot are fresh 0.3.0
builds from the series above.

## 8. Fixes landed on this branch

In-scope (`platform/`, `build/`):

- `platform/rg35xx-h/rootfs/stage-userland.sh`: absolutize `--staging`
  and `--cache` (`realpath -m`) — relative paths broke the
  `userland-provenance` redirect (resolves inside a `cd`'d subshell)
  and debootstrap's absolute `--cache-dir` demand. Same fix class as
  the WP2 `build-kernel.sh`/`build-uboot.sh` absolutization.
- `platform/rg35xx-h/rootfs/overlay/etc/os-release`: `0.2.0-exp2` ->
  `0.3.0-exp3`.

Cross-tree, needs owner review:

- `docs/test-results/v03-image.md` (this file; Agent 6).

## 9. Open gaps (not blockers for this image)

1. Physical boot (H1-H18) still needs RG35XX H hardware; panel
   timings + DDR3 TPR stay hardware-gated (UART log pending).
2. mke2fs is 1.47.0, so the ext4 wrapper still varies run-to-run
   (payload bytes proven stable); container TODO (>= 1.47.1) stands.
3. 13 noble closure libs remain (same as 0.2.0); trixie migration later.
