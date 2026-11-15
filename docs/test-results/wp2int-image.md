# WP2 merged-image integration — test results

Date: 2026-11-15. Branch: `wp2int/image`. Code HEAD: `bef4be9`.
Host: `DESKTOP-OVMHVD2` (Ubuntu 24.04 x86_64, 12 cores).

Owner note: written by the WP2 merged-image integrator on Workflow task
instruction; `docs/test-results/` is Agent 6's tree — code fixes are on
this branch, flagged for owner review (see §8).

## Summary

First TRUE experimental image from merged main: kernel + U-Boot (both
DDR variants) + 7-patch squeezeplay + kmsdrm SDL2 + sdl12-compat +
evdev2jive/drm_splash + skins + asound + audio-owner + standalone
(ship-disabled) + BSP applet + kernel modules + target lib closure.

| Check | Status | Notes |
|---|---|---|
| fetch | PASS | linux tarball sha + u-boot/atf SHAs verified |
| uboot:ddr3+ddr4 | PASS | SPL+itb both variants, SHAs identical to WP2 |
| kernel | PASS | Image + DTB (DTB identical to WP2) + 1676 .ko |
| core:7/7 | PASS | patches apply clean; cross build exit 0 |
| core:arch/strings | PASS | all-ELFs aarch64, RUNPATH exact, patch strings in |
| ui:bins | PASS | evdev2jive/drm_splash/test_splash cross, qemu ALL PASS |
| sdl:compat+smoke | PASS | compat 1.2.78 cross; sdl_smoke ALL PASS under qemu |
| sdl:kmsdrm | PASS | SDL2 2.32.10 cross with kmsdrm(dynamic)+gles2+udev |
| sym:closure | PASS | 0007 fixed jive/SDL_EventQueueLength; sweep clean |
| bsp:applet | PASS | applet loads error-free; skin RG35XXHBaseSkin selected |
| boot:qemu | PASS | jive 9.0.0 r541 main loop, 51 applets, settings stored |
| rootfs:stage | PASS | stage-payload.sh: 4685 files, manifests, NEEDED-clean |
| image:ddr3+ddr4 | PASS | both variants exit 0 at exact /tmp/sqz-merged paths |
| image:validate | PASS | gate PASS; 4685/4685 image bytes match staging |
| boot:target | NOT RUN | no RG35XX H hardware (sole external blocker) |

Totals — PASS: 14, FAIL: 0, NOT RUN: 1, BLOCKED: 0.

## Details

### fetch — PASS

Target: `manual` (pinned boot chain, `SOURCE_DATE_EPOCH=1794334272`).

```text
$ ./platform/rg35xx-h/kernel/fetch.sh --fetch all
fetch.sh: cached .../linux-7.3.4.tar.xz OK          # sha256 b11b6df8...01d9
fetch.sh: in-tree RG35XX DTS chain present
fetch.sh: cached .../u-boot-2026.10 OK (55084065...db2)
fetch.sh: ... ready (anbernic_rg35xx_h700_defconfig present)
fetch.sh: cached .../atf-2.15.0 OK (da738d5e...d757)
```

Upstream trees were seeded from the verified WP2 platform cache on the
same host (no network re-fetch); every pin was re-verified by hash/SHA
above. Linux was extracted fresh from the tarball (prior tree carried
build state); u-boot/ATF git trees verified at pinned SHAs.

### uboot:ddr3+ddr4 — PASS

Target: `manual` (rootless sysroot `/tmp/wp2sys` + host python3, §8).

```text
$ ./platform/rg35xx-h/kernel/build-uboot.sh --uboot ... --atf ... \
    --out build/cache/uboot --variant both --jobs 4
UBOOT_EXIT=0
d71deea5...044a36  ddr3/bl31.bin                  (41060)
33bd339b...0666752  ddr3/u-boot-sunxi-with-spl.bin (758281)
792faf84...c0c906  ddr3/u-boot.itb                (716297)
d71deea5...044a36  ddr4/bl31.bin
edfcbce2...28fb8d8  ddr4/u-boot-sunxi-with-spl.bin (758281)
792faf84...c0c906  ddr4/u-boot.itb
```

All six SHAs are byte-identical to the WP2 platform record
(`docs/test-results/wp2-platform.md` §2): merged scripts reproduce the
bootloader bit-for-bit. `obj-ddr3/.config` has
`SUNXI_DRAM_H616_DDR3_1333=y`, ddr4 has `LPDDR4=y` (1 match each).

### kernel — PASS

Target: `manual`.

```text
$ ./platform/rg35xx-h/kernel/build-kernel.sh --src ... --out build/cache/kernel --jobs 8
KERNEL2_EXIT=0
7c22dbb7e6c4b91491b848f54002c8852ad7316815f7930bb69e59fd176d06fe  boot/Image
b8b0bfa32b93c3811df7cd168f46f220c3d7ea9723eeb94d3dd5e77f819f5412  dtbs/...rg35xx-h.dtb
boot/Image 53901824, DTB 28301, modules 1676 .ko (379M)
Linux version 7.3.4 (builder@repro) ... # SMP PREEMPT Tue Nov 10 18:11:12 UTC 2026
fragment: SND_SUN8I_CODEC=y SND_SUN50I_CODEC_ANALOG=y RTW88_8821CS=m
          DRM_SUN4I=y EXT4_FS=y VFAT_FS=y MMC_SUNXI=y
```

The DTB is byte-identical to WP2. The first Image build differed from
WP2's (same size) because kbuild embeds wall-clock `UTS_VERSION`
unless `KBUILD_BUILD_TIMESTAMP` is set (verified in the version
string; kernel `.config` otherwise effectively identical — only
host-rustc probe lines differ). Fixed in `build-kernel.sh` on this
branch (timestamp + `builder@repro` user/host pinned from epoch);
above is the rebuilt, pinned result (version string == epoch).

### core:7/7 — PASS

Target: `manual` (pristine `squeezeplay@758bc11` clone + merged
`Makefile.linux-aarch64`, `/tmp/x-tools` sysroot).

```text
$ for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < $p; done
PRISTINE_PATCHES=7/7
$ make -f Makefile.linux-aarch64 SYSROOT=/tmp/x-tools
SQ2_EXIT=0
ecdb8d8e3a397e33aac484dc6eb1658cdc0937962f572145cd7d0b5059b7f8bb
  squeezeplay-aarch64-9.0.0.tgz   (23534157 bytes)
```

0007 (new on this branch, needs Agent 2 review): jive called the
SDL-internal `SDL_EventQueueLength()`, which sdl12-compat does not
export — jive aborted at startup under BIND_NOW. Replaced with the
public-API `SDL_PeepEvents(NULL, 0, SDL_PEEKEVENT, SDL_ALLEVENTS)`
count (same TU already uses `SDL_PeepEvents`). Found by booting the
staged image stack under qemu (see sym:closure).

### core:arch/strings — PASS

```text
RUNPATH [/opt/squeezeplay/lib] x3 (jive, jive_alsa, lua), exact
jive_alsa NEEDED: libm libasound.so.2 libc ld-linux (only ALSA user)
jive_alsa strings: Negotiated PCM + 2 clamp lines (0004/0005)
jive strings: AUDIO_OWNER_BIN (0006)
ELF sweep: every bin/lib ELF aarch64, 0 exceptions; 49 applet dirs
jive_alsa -b 1 -p 99 under qemu: both clamp WARNs fire, then clean
  pcm_test failure (no /dev/snd on host, expected)
```

### ui:bins — PASS

Target: `manual` (BRINGUP appendix A recipe, `/tmp/wp2-ui/tc` sysroot).

```text
EVDEV_OK DRM_OK TEST_OK (zero warnings, all ARM aarch64)
qemu test_splash: bright headline pixels = 10688; splash tests: ALL PASS
qemu evdev2jive --dump-map rg35xxh.map: parses (gpio-keys/adc-joystick)
```

### sdl:compat+smoke — PASS

sdl12-compat 1.2.78 via `ui/vendor/fetch-sdl12-compat.sh` (sha-verified
`40ec5f0b…da11a`) + SDL2 2.32.10 fixture (tarball sha `5f5993c5…a5165`):

```text
libSDL-1.2.so.1.2.78 aarch64, SONAME libSDL-1.2.so.0, NEEDED libc only
sdl_smoke under qemu (SDL_VIDEODRIVER=dummy):
  SDL_Init: OK / video driver: dummy / SetVideoMode: OK 640x480 bpp=16
  FillRect+Flip: OK / sdl_smoke: ALL PASS
```

### sdl:kmsdrm — PASS

Real kmsdrm-capable SDL2 2.32.10 cross-build (NOT the fixture): noble
arm64 debs (libdrm/libgbm/EGL/GLES/libudev/libxkbcommon/libinput/...
34 debs, consistent noble-release set) extracted to a scratch sysroot;
configure with `PKG_CONFIG_LIBDIR/SYSROOT_DIR` + udev CPPFLAGS/LDFLAGS:

```text
CONF_EXIT=0 BUILD_EXIT=0 INSTALL_EXIT=0
Audio drivers   : disk dummy oss
Video drivers   : dummy offscreen kmsdrm(dynamic) opengl opengl_es2 vulkan
Input drivers   : linuxev linuxkd
Using libudev   : YES / Using dbus : NO
libSDL2-2.0.so.0.3200.10 aarch64, NEEDED libm/libc only (backends dlopen),
  148 kmsdrm string refs, zero X11/Wayland refs.
```

Two genuine build bugs hit and fixed: (1) SDL_egl.c compiles out when
desktop OpenGL is disabled (kmsdrm needs the EGL glue — keep
`--enable-video-opengl`); (2) stale fixture objects poison a copied
tree (always fresh-extract). SDL2 2.32 consumes neither libinput nor
xkbcommon directly (evdev kbd); both stay available for SDL3/future.

Shipped runtime closure: 19 libs (libdrm/libgbm/glvnd EGL+GLES2/
libudev/libasound/libz + link deps), DT_NEEDED-clean. The Mesa DRI
payload (libEGL_mesa + panfrost_dri + 120M LLVM) is deliberately NOT
shipped: the panel driver itself is still OOT/hardware-gated, so GLES
cannot run on first boot; SDL falls back to the software renderer
(BRINGUP §2 path) until the display stack lands. Deb recipe recorded
in this doc (§ How to reproduce); closure tooling kept in /tmp note.

### sym:closure — PASS

Symbol-level sweep of all 1732 staging ELFs (undefined vs staging
defined + base glibc/jive-process sets): exactly ONE real gap —
`SDL_EventQueueLength` (jive) — fixed by 0007 (see core:7/7). Rest:
libc/libm (base userland) + jive-process symbols for dlopen'd Lua
modules (rtmp, rg35xxh_bsp — by design). DT_NEEDED sweep: CLOSURE_CLEAN.

### bsp:applet — PASS

Two BSP applet bugs found by the qemu boot and fixed on this branch
(needs Agent 2 review; both one-spot, same-file):

1. `SqueezeboxRG35XXHApplet.lua` uses `module(...,
   jive.ui.Framework.constants)` (stock convention) but captured only
   `tonumber, tostring, pairs` as locals — bare `pcall`/`type` uses
   resolved to nil (`attempt to call global 'pcall' (a nil value)`).
   Fix: capture `pcall, type` too (LinuxApplet captures the same way).
2. `initPower` iterated one `lfs.dir` iterator in two loops; lfs closes
   the DIR\* at exhaustion, so the second loop raised `bad argument #1
   to '(for generator)' (closed directory)`. Fix: single pass keeping
   the first non-dot entry as fallback.

`luac -p` clean (host + aarch64). After the fix the applet registers
with zero errors and the C uevent pump delivers events to a working
`_onUevent` (errors observed pre-fix prove the pump path is live).

### boot:qemu — PASS

Target: `manual` (qemu-aarch64 8.2.2; merged root = image staging
`opt/` + target libc sysroot + test-only `fakevideo.so`/`logconf.lua`
in the qemu root — neither ships in the image).

```text
$ SDL_VIDEODRIVER=dummy qemu-aarch64 -L a64root \
    -E LD_PRELOAD=/opt/squeezeplay/lib/fakevideo.so \
    -E LD_LIBRARY_PATH=/opt/squeezeplay/lib ./jive
JIVE_RC=124 (alive at the 60 s timeout = main loop running)
SqueezePlay version 9.0.0 r541
640,480 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]
Registering: x51 applets (48 stock + SqueezeboxRG35XXH +
  RG35XXHBaseSkin + RG35XXHLandscapeSkin)
store settings: DesktopJive, SetupAppletInstaller, SlimDiscovery, ...
select skin: RG35XXHBaseSkin
```

No FATAL/crash/symbol errors. `LD_LIBRARY_PATH=$PREFIX/lib` in the
qemu run mirrors the platform launcher (it is what lets compat
dlopen the local SDL2 — proven necessary and sufficient here).
Remaining log noise is the known pre-existing upstream `start_demo`
diagnostic (WP1/WP2-noted).

### rootfs:stage — PASS

Target: `manual` (`mkrootfs.sh` + new `stage-payload.sh`).

```text
$ ./platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch 1794334272
staging ready: build/cache/rootfs (14 files)
$ ./build/image/stage-payload.sh --staging build/cache/rootfs \
    --core-tgz .../squeezeplay-aarch64-9.0.0.tgz --uibins ... \
    --sdl2 .../sdl2-kmsdrm --compat .../sdl12-compat \
    --bsp-so .../rg35xxh_bsp.so --squeezeplay-src .../src \
    --kernel-modules build/cache/kernel/modules \
    --target-libs .../target-libs.txt --epoch 1794334272
core extracted: 3103 members / dev payload pruned
SDL stack installed (compat 1.2.78 + SDL2 2.32.10 kmsdrm)
install.sh: staged 479 files / audio payload staged
standalone staged (disabled: no wants symlinks)
BSP applet + module staged / kernel modules staged
target libs staged (19 files)
payload ready: build/cache/rootfs (4685 files)
```

Staging audits: 1732 ELFs all aarch64 (0 exceptions); prune verified
(no `include/`, `share/man`, `*-config`, jpeg tools, `.a/.la`,
unversioned `.so`); compat shadow verified (`libSDL-1.2.so.0 ->
1.2.78`, no `0.11.4`); BSP applet (4 files) + module present; only
splash/wifi/squeezeplay enabled (standalone units present, no wants
links); `/payload-manifest.txt` + `manifest.*` written and
epoch-clamped. DT_NEEDED closure: CLOSURE_CLEAN (see sym:closure).

### image:ddr3+ddr4 — PASS

Target: `manual` (`assemble-image.sh`, epoch 1794334272, both exit 0).

```text
/tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img  2147483648 bytes
  380be5770fe7146d25896935bf8d802649fd32e3f4630679e4cd961ff1da2187
/tmp/sqz-merged/squeezebox-rg35xxh-ddr3.img  2147483648 bytes
  82b3de0a7fb59f7b66586cbba63071ab07d08065a41c20ab26999c9a9146ba25
```

(`.sha256` sidecars written next to each image by the assembler.)

### image:validate — PASS

Target: `manual` + `tests/check_image.py` (both images).

```text
$ python3 tests/check_image.py .../squeezebox-rg35xxh-ddr4.img .../ddr3.img
[image] protective MBR ok (0xEE, boot sig)
[image] GPT primary header CRC ok / array at sunxi LBA 4096 ok
[image] p1 BOOT: 32768..557055 ok / p2 ROOTFS: 557056..4194271 ok
[image] GPT backup header ok / SPL blob present at sector 16
[image] boot file present: BOOT.SCR / IMAGE / DTB.IMG (x2)
[image] no-secrets scan clean (x2)
[image] checked 2 target(s), 0 problem(s)
[RESULT] image: PASS
$ sfdisk -d .../ddr4.img   # disk 0A1B2C3D-0000-..., p1 EFI-System
  ...-0001-..., p2 Linux ...-0002-..., first-lba 4128: all match
$ file ...                 # DOS/MBR boot sector, ID=0xee
SPL: first 758281 bytes cmp-equal to staging (both variants),
  503-byte pad all zero; SPL 1482 sectors at LBA 16 (ends 1498 < 4096)
FAT (mdir): SQUEEZEBOOT, serial 6AF3-5E40 (epoch volid),
  boot.scr 849 + Image 53901824 + dtb.img 28301, epoch-dated;
  extracted Image/dtb SHAs match kernel staging; fsck.vfat exit 0
ext4: UUID 0a1b2c3d-...-0001, label squeezebox-root, hash seed pinned
  ...-0002, e2fsck -f clean (5489 files, 127328 blocks)
debugfs full dump of p2 vs staging manifest.sha256: 4685/4685 OK —
  every payload byte in the image is bit-identical to staging.
Cross-variant: 52335 diff bytes = 24793 SPL region (== WP2 count) +
  27542 ext4 1.47.0 wrapper (scales with 4685 inodes vs WP2's 371 for
  15 files); all pre-p2 diffs inside the SPL blob (max offset 46179);
  GPT+SPL-placement+FAT bit-identical across variants.
```

mke2fs on this host is 1.47.0, so the ext4 wrapper still varies
run-to-run (the assembler warns as designed); the container TODO
(e2fsprogs >= 1.47.1) from WP2 stands. Payload bytes are unaffected
(4685/4685 proof above).

### boot:target — NOT RUN

No RG35XX H hardware on this host. First-boot procedure:
`docs/test-results/HW_TEST_PLAN.md` (H1–H18) + `ui/BRINGUP.md` +
`audio/BRINGUP.md`. Known pre-hardware gaps: OOT panel driver
(display stays dark), DDR3 TPR tuning, base userland (below).

## Fixes landed on this branch

In-scope (`platform/`, `build/`, install wiring):

- `platform/rg35xx-h/services/squeezeplay.sh`: exec the real binary
  `$PREFIX/bin/jive` (was nonexistent `bin/squeezeplay`); export
  `LD_LIBRARY_PATH=$PREFIX/lib` so sdl12-compat finds the local SDL2.
- `platform/rg35xx-h/services/splash.sh`: Agent-4 provider is now
  `/opt/squeezeplay/bin/init-splash.sh show` (was nonexistent
  `/usr/share/squeezebox/splash-show`); fbi/banner fallbacks kept.
- `platform/rg35xx-h/services/systemd/splash.service`: added
  `ConditionPathExists=/dev/dri/card0` (BRINGUP expects it) +
  `ExecStop=-.../init-splash.sh stop`.
- `platform/rg35xx-h/services/systemd/squeezeplay.service`: added
  `ExecStartPre=-.../init-splash.sh stop` (DRM handoff, SERVICE_HOOKS).
- `platform/rg35xx-h/services/README.md`: paths updated to match.
- `platform/rg35xx-h/kernel/build-kernel.sh`: pin
  `KBUILD_BUILD_TIMESTAMP` + `builder@repro` user/host from epoch
  (unpinned wall clock made every Image unique).
- `build/image/stage-payload.sh` (new): reproducible payload layering
  (core+prune+SDL/UI/audio/standalone/BSP/modules/libs/manifests).
- `build/image/README.md`: build chain documents the new step.

Cross-tree, needs owner review (separate commits, revertable):

- `squeezeplay/patches/0007-...` + `series` + `README.md`: jive
  `SDL_EventQueueLength` → public `SDL_PeepEvents` count (Agent 2).
  Without it jive aborts at startup against sdl12-compat.
- `squeezeplay/configuration/rg35xxh_bsp/.../SqueezeboxRG35XXHApplet.lua`:
  capture `pcall, type` locals; single-pass `initPower` dir scan
  (Agent 2). Without them the applet errors on every boot.

Host-env notes (not committed; container equivalents are TODOs):

- Rootless sysroot `/tmp/wp2sys` + `CPATH` (multiarch + python3.12) +
  host `python3` shadow (sysroot python lacks setuptools).
- SDL2 kmsdrm deps: 34 noble arm64 debs from ports.ubuntu.com by pool
  path (see sdl:kmsdrm); recipe ends at the `staging/sdl2-kmsdrm`
  prefix consumed by `stage-payload.sh --sdl2`.
- `build/docker/Dockerfile` does not yet install the ALSA-cross,
  cmake, or kmsdrm-deb layers needed to replay this chain
  containerized — recorded, not changed (no daemon to test with).

## Open gaps (not blockers for this image)

1. Base userland: no glibc/systemd/coreutils/busybox in the image
   (skeleton + payload only). Debootstrap/buildroot decision + size
   budget still open (WP2-noted). The image does not boot to
   userspace yet; all validation above is host-side + qemu-user.
2. OOT panel driver + DT overlay: display stays dark on hardware;
   carries the WP1/WP2 hardware gate. DRM splash + kmsdrm paths are
   staged and unit-proven, awaiting first light.
3. Mesa DRI payload (EGL_mesa + panfrost + LLVM ~150M): recipe proven
   fetchable; ship when (2) lands and GLES is measurable.
4. DDR3 TPR tuning + unit DRAM-ID method: still hardware-gated.
5. `build/docker` container gap (see above).

## How to reproduce

```sh
git checkout wp2int/image
# 1. boot chain (rootless sysroot env; see Host-env notes)
./platform/rg35xx-h/kernel/fetch.sh --fetch all
./platform/rg35xx-h/kernel/build-uboot.sh --uboot build/cache/upstream/u-boot-2026.10 \
    --atf build/cache/upstream/atf-2.15.0 --out build/cache/uboot --variant both
./platform/rg35xx-h/kernel/build-kernel.sh --src build/cache/upstream/linux-7.3.4 \
    --out build/cache/kernel
# 2. squeezeplay (/tmp/x-tools ALSA sysroot)
git clone <squeezeplay> /tmp/sp && cd /tmp/sp && git checkout 758bc11
cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < $p; done
cd src && make -f Makefile.linux-aarch64 SYSROOT=/tmp/x-tools
# 3. UI bins + compat + kmsdrm SDL2 (ui/BRINGUP.md appendix A + sdl:kmsdrm)
# 4. rootfs + payload + images
./platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
    --with-services --with-config --epoch 1794334272
./build/image/stage-payload.sh --staging build/cache/rootfs [...] \
    --epoch 1794334272
./build/image/assemble-image.sh --variant ddr4 --uboot build/cache/uboot \
    --kernel build/cache/kernel --rootfs build/cache/rootfs \
    --out /tmp/sqz-merged/squeezebox-rg35xxh-ddr4.img   # + ddr3
# 5. gates
bash tests/selftest.sh
python3 tests/check_image.py /tmp/sqz-merged/*.img
```

## Files changed (this branch)

- `platform/rg35xx-h/services/{squeezeplay.sh,splash.sh,README.md}`
- `platform/rg35xx-h/services/systemd/{splash,squeezeplay}.service`
- `platform/rg35xx-h/kernel/build-kernel.sh`
- `build/image/stage-payload.sh` (new), `build/image/README.md`
- `squeezeplay/patches/0007-*.patch` (new), `series`, `README.md`
- `squeezeplay/configuration/rg35xxh_bsp/.../SqueezeboxRG35XXHApplet.lua`
- `docs/test-results/wp2int-image.md` (this file)