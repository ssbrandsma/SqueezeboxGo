# Build guide — every binary, end to end

How to reproduce every build artifact in this project on Ubuntu 24.04
(WSL). All commands run from the repo root unless noted. Every script
prints its own usage with `--help` or `--dry-run`; this guide shows the
order and the exact invocations the 0.2.0-exp2 release used.

Related: [build contract](build.md), [pins](../platform/rg35xx-h/kernel/pins.env),
[upstream manifest](upstream-references/upstream-manifest.md),
[toolchain notes](../build/toolchain/sysroot-notes.md).

## 0. Prerequisites

- Ubuntu 24.04, `git`, `curl`, `python3`, `sha256sum`, `xz-utils`.
- Cross toolchain: `gcc-aarch64-linux-gnu` 13.x (or the pinned container).
- Kernel extras: `bc bison flex libssl-dev device-tree-compiler`
  (full list: [build/docker/Dockerfile](../build/docker/Dockerfile)).
- Image assembly: `sfdisk mkfs.ext4 mkfs.vfat mcopy mkimage dd fakeroot`
  (check any time: `build/image/assemble-image.sh --check-deps`).
- Userland: `debootstrap dpkg-deb wget` (or Docker for the container path).
- Emulation/smoke: `qemu-user`, `file`, `readelf`, `debugfs`, `e2fsck`.
- Rust (Spotify only): rustup + `aarch64-unknown-linux-gnu` target, ≥1.85.
- Reproducibility: always export `SOURCE_DATE_EPOCH` (use the HEAD commit
  time: `export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)`).

Two build styles are supported and produce equivalent results:

- **Host build** (what 0.2.0-exp2 used): tools installed on Ubuntu 24.04.
- **Container build**: `build/docker/build.sh -- <command>` runs any repo
  command inside `debian:bookworm-slim@sha256:734a72b3…` with all tooling.
  Toolchain work also has `build/toolchain/Dockerfile` (noble + arm64
  multiarch). Neither image was rebuilt by daemon-less agents; Dockerfiles
  are pinned and reviewable but treat the first `docker build` as untested.

## 1. Full pipeline (release order)

```sh
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
CACHE=build/cache/upstream   # gitignored fetch dir

# 1a. Fetch + verify pinned boot-chain sources (sha256 / git-SHA checked)
platform/rg35xx-h/kernel/fetch.sh --fetch all --dir $CACHE

# 1b. Bootloader: ATF BL31 (shared) + U-Boot SPL+ITB per DRAM variant
platform/rg35xx-h/kernel/build-uboot.sh \
  --uboot $CACHE/u-boot-2026.10 --atf $CACHE/atf-2.15.0 \
  --out build/cache/uboot --variant both

# 1c. Kernel: apply OOT series, defconfig + fragment, Image/modules/DTBs
platform/rg35xx-h/kernel/build-kernel.sh \
  --src $CACHE/linux-7.3.4 --out build/cache/kernel

# 1d. Base userland: debootstrap trixie minbase (fakeroot, unprivileged)
platform/rg35xx-h/rootfs/stage-userland.sh --staging build/cache/rootfs

# 1e. Squeezebox rootfs layer: skeleton + overlay + services + config
platform/rg35xx-h/rootfs/mkrootfs.sh --staging build/cache/rootfs \
  --with-services --with-config --epoch $SOURCE_DATE_EPOCH

# 1f. SqueezePlay cross build (Section 2) -> squeezeplay-aarch64-*.tgz
# 1g. UI/SDL cross builds (Section 3) -> evdev2jive, drm_splash, libs
# 1h. Payload: core + SDL + UI + audio + standalone + BSP + modules + libs
build/image/stage-payload.sh --staging build/cache/rootfs \
  --core-tgz <1f-tarball> --uibins <1g-dir> --sdl2 <1g-sdl2> \
  --compat <1g-compat> --bsp-so <rg35xxh_bsp.so> \
  --squeezeplay-src /tmp/squeezeplay \
  --kernel-modules build/cache/kernel/modules \
  --target-libs <closure-list> --epoch $SOURCE_DATE_EPOCH

# 1i. Images, both DRAM variants (unprivileged, no loop mounts)
build/image/assemble-image.sh --variant ddr4 \
  --uboot build/cache/uboot --kernel build/cache/kernel \
  --rootfs build/cache/rootfs --out /tmp/sqz/squeezebox-rg35xxh-ddr4.img
build/image/assemble-image.sh --variant ddr3 ... # same, ddr3

# 1j. Verify + release artifacts
IMAGE_UNDER_TEST=/tmp/sqz/...-ddr4.img scripts/build-and-check.sh
python3 tests/check_image.py /tmp/sqz/...-ddr3.img /tmp/sqz/...-ddr4.img
xz -T0 -6 /tmp/sqz/*.img && releases/checksum.sh  # SHA256SUMS + manifest
```

## 2. SqueezePlay (jive + Lua + codecs)

- Source: `ralph-irving/squeezeplay@758bc11`, fetched to `/tmp` (never
  committed); recipe in [vendor-notes](../squeezeplay/upstream/vendor-notes.md).
- Patches: `squeezeplay/patches/0001..0007` + `series` (see
  [patches README](../squeezeplay/patches/README.md) for what each does).
- Makefile: `squeezeplay/configuration/Makefile.linux-aarch64`
  (lineage: upstream `Makefile.linux` + tcz-jivelite aarch64 recipe,
  retuned to `-march=armv8-a+crc -mtune=cortex-a53`,
  `PREFIX=/opt/squeezeplay`, PUC Lua 5.1.5 shared-lib, no tslib/X11).

```sh
SP=/tmp/squeezeplay   # pristine 758bc11 checkout
cp squeezeplay/configuration/Makefile.linux-aarch64 $SP/src/
cd $SP/src
for p in $OLDPWD/squeezeplay/patches/000*.patch; do patch -p1 < $p; done
make -f Makefile.linux-aarch64            # cross (default)
# native x86_64 validation instead:
# make -f Makefile.linux-aarch64 CROSS_COMPILE= ARCHFLAGS="-march=x86-64" LUA_ARCHFLAGS="-s -O2"
```

- Targets: `all = check-deps sdl-all lua-all app`; `sdl-all` builds
  zlib/expat/freetype/SDL/SDL_image/SDL_ttf/SDL_gfx/libpng/libjpeg;
  `lua-all` builds Lua 5.1.5 + 10 C modules; `app` builds jive,
  jive_alsa, codecs (fdk-aac, flac, libmad, tremor, ogg), fonts.
- Only external target dep: ALSA headers/lib (`libasound2-dev:arm64`
  in container, or `SYSROOT=<firmware-rootfs>`); everything else is
  vendored. `check-deps` fails fast if ALSA is missing.
- Output: `build/linux-aarch64/opt/squeezeplay/...` → tarred as
  `squeezebox-aarch64-*.tgz` for `stage-payload.sh --core-tgz`.
  Validate: `file` → ARM aarch64, `RUNPATH=/opt/squeezeplay/lib`,
  `jive_alsa NEEDED libasound.so.2` (see `sysroot-notes.md`).
- Smoke: `qemu-aarch64 ./jive` boots to the main loop (dummy video);
  10/10 Lua modules load (evidence: `docs/test-results/wp2-core.md`).

## 3. UI / SDL binaries

Contract flags: `-march=armv8-a+crc -mtune=cortex-a53 -O2`
(plus `--sysroot=$TC` on hosts; plain `aarch64-linux-gnu-gcc` in container).
Full appendix: `ui/BRINGUP.md`.

```sh
CC="aarch64-linux-gnu-gcc --sysroot=$TC"
CF="-march=armv8-a+crc -mtune=cortex-a53 -O2"
# input mapper (libc + kernel headers only)
$CC -std=c99 -Wall -Wextra $CF -o evdev2jive ui/input/evdev2jive.c
# splash painter + its test (libc + zlib)
$CC -std=c99 -Wall -Wextra $CF -o drm_splash \
  ui/splash/drm_splash.c ui/splash/pngmini.c ui/splash/blit.c -lz
# sdl12-compat 1.2.78 (pinned, sha-verified) against SDL2 headers:
SRC=$(ui/vendor/fetch-sdl12-compat.sh)
cmake -S $SRC -B build-compat -DCMAKE_TOOLCHAIN_FILE=<aarch64-tc.cmake> \
  -DSDL2_INCLUDE_DIR=$STAGE/include/SDL2 -DSDL12TESTS=OFF \
  -DSDL12DEVEL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-compat   # -> libSDL-1.2.so.0 (aarch64, NEEDED libc only)
```

SDL2: fixture config (dummy video, everything off) exists only to compile
compat; the SHIPPED SDL2 2.32.10 is built `--host=aarch64-linux-gnu` with
kmsdrm(dynamic) + opengles2 + udev, NEEDED libc/m, 0 X11 refs. Verify all
six artifacts with `file` → ARM aarch64; run `ui/input/tests/run_tests.sh`
(13/13) and the qemu SDL-smoke (`ui/tests/sdl_smoke.c`).

Skins regenerate deterministically (never hand-edit generated files):
`ui/skins/scale_qvga_2x.py --src /tmp/squeezeplay --out ui/skins`
must be a no-op afterwards (`git status` clean). Splash likewise:
`ui/splash/make_splash.py` regenerates `splash_640x480.png` byte-identically.

## 4. Boot chain, userland, image

- Fetch/verify: `fetch.sh --print-pins` (offline) / `--fetch all` / `--check`.
  Linux tarball sha256 comes from kernel.org `sha256sums.asc`.
- U-Boot: `--variant both` builds shared BL31 once, then ddr4 (defconfig
  as-is, LPDDR4) and ddr3 (+ `uboot-rg35xx-h-ddr3-fragment.conf`,
  `SUNXI_DRAM_H616_DDR3_1333`). Outputs per variant:
  `u-boot-sunxi-with-spl.bin`, `u-boot.itb`, `bl31.bin` + SHA256SUMS.
- Kernel: applies `patches/series` (`--forward`, fails loudly), appends the
  config fragment to `defconfig`, `olddefconfig`, `Image modules dtbs`,
  installs to `--out/{boot,dtbs,modules}`. UTS + wall clock pinned via
  `KBUILD_BUILD_TIMESTAMP/USER/HOST` for reproducibility.
- Userland: `stage-userland.sh --staging DIR` (default trixie — bookworm
  cannot run the payload, GLIBC_2.38; see ADR-0004). Unprivileged fakeroot
  debootstrap + rootless second stage; postinst runs at first boot via
  `squeezebox-firstboot.service`. Docker fallback: `--userland container`
  prints the exact privileged recipe. Package set: `userland-include.txt`
  (systemd, udev, ALSA, iw/wpasupplicant, openssh-server, firmware-realtek…).
- Payload/rootfs/image: `mkrootfs.sh` (skeleton+overlay+services+manifests)
  → `stage-payload.sh` (core/SDL/UI/audio/standalone/BSP/modules/libs +
  `payload-manifest.txt`) → `assemble-image.sh` (GPT via `mksunxi_gpt.py`,
  SPL@sector16, FAT `boot.scr`/`Image`/`dtb.img`, ext4 `-d`, verify+sha256).
  Layout: `build/image/partitions.txt`. Always `--dry-run` first after
  script changes; `--check-deps` lists missing host tools.

## 5. Spotify backend (Rust)

```sh
cd /tmp/librespot && git checkout v0.8.0   # verify d36f9f19
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
  CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
  PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig \
  PKG_CONFIG_ALLOW_CROSS=1 \
  CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS='-C target-cpu=cortex-a53'
cargo build --release --locked --target aarch64-unknown-linux-gnu \
  --no-default-features --features alsa-backend,rustls-tls-webpki-roots,with-libmdns
```

Result: ~20 MB aarch64 ELF, NEEDED libasound+libgcc+libc/m only
(no OpenSSL — rustls is static). Wiring: `spotify.conf` (LIBRESPOT_* env),
`spotify-run.sh` (pins `--backend/--device/--mixer/--onevent/
--emit-sink-events`), `spotify-onevent.sh` (PLAYER_EVENT → Now Playing).
Tests: `standalone/tests/test-librespot.sh` with `LIBRESPOT_BIN` set
(97/97 with the real binary). `cargo vendor` + SBOM for offline image
builds is a recorded TODO.

## 6. Reproducibility + troubleshooting

- Repro levers: `SOURCE_DATE_EPOCH` everywhere (staging mtimes, FAT volid,
  kernel UTS), `TZ=UTC0` for FAT, `clamp-fat.py`, ext4 `hash_seed` pin.
  Bit-identical ext4 needs `mke2fs ≥ 1.47.1` (script warns otherwise);
  file *payloads* are proven stable regardless.
- `file` says x86-64? You forgot `CROSS_COMPILE` (native build) — check
  `readelf -d` RUNPATH too. `jive` aborts with symbol lookup error?
  Rebuild against sdl12-compat (patch 0007 documents the one internal
  symbol). Bookworm userland + `GLIBC_2.38 not found`? Use trixie.
- Slow steps: kernel Image+modules (~30-60 min), debootstrap (~10 min),
  `xz -T0 -6` on 2 GiB (~5 min). Everything else is seconds/minutes.
- Keep `build/cache/` (gitignored) between runs: fetch scripts resume from
  verified cached downloads.
