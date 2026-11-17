# Build SqueezeboxGo — every input, pack, deploy

How to reproduce the App Center ZIP from this repo on Ubuntu 24.04
(host or WSL). All commands run from the repo root unless noted.
Firmware-image builds are separate: [BUILD-GUIDE.md](BUILD-GUIDE.md).

Provenance: this recipe produced `0.2.10` (Jammy tarball sha256
`673ec5ee…`, fbcon libSDL sha256 `3924a625…`). Always export
`SOURCE_DATE_EPOCH` first (pack uses it for reproducible archives):

```sh
export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
```

## 0. Prerequisites

- Ubuntu 24.04, `git curl python3 unzip sha256sum xz-utils patch file readelf`.
- Cross toolchain for the aarch64 builds: `gcc-aarch64-linux-gnu`
  13.x (or the rootless `/tmp/x-tools` cache the diags used).
- `qemu-user` (`qemu-aarch64`) for userspace smoke checks.
- Device (RG35XX H, stock firmware) for deploy + live verification.
- Upstream squeezeplay source is fetched to `/tmp`, never committed:
  `ralph-irving/squeezeplay@758bc110e16de4a61905e19d012a0ad25d97859b`
  (r541). Pins: [EXTERNAL-SOURCES.md](EXTERNAL-SOURCES.md),
  [vendor-notes](../squeezeplay/upstream/vendor-notes.md).

## 1. The two big inputs (aarch64, glibc ≤ 2.35)

Stock Jammy ships glibc 2.35; a noble-built tree needs GLIBC_2.38 and
cannot start there. Both inputs are built against a pinned Jammy
sysroot so the maximum requirement is GLIBC_2.34 (measured).

### 1a. Jammy sysroot (rootless, SHA256-pinned)

```sh
build/toolchain/jammy-sysroot.sh --prefix /tmp/jammy-sysroot
eval "$(build/toolchain/jammy-sysroot.sh --env --prefix /tmp/jammy-sysroot)"
build/toolchain/jammy-sysroot.sh --check --prefix /tmp/jammy-sysroot
# want: "probe max GLIBC: GLIBC_2.34" + "CHECK OK"
```

Why wrappers (`-B… -isystem…`, not bare `--sysroot`): the toolchain's
noble 2.39 headers otherwise win and emit `__isoc23_*` refs. Full
rationale: `squeezeplay/configuration/jammy-staging.md`.

### 1b. SqueezePlay tree tarball

```sh
git clone https://github.com/ralph-irving/squeezeplay /tmp/jammy-sp/squeezeplay
cd /tmp/jammy-sp/squeezeplay
git checkout 758bc110e16de4a61905e19d012a0ad25d97859b
cp <repo>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <repo>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done  # 7/7
cd src
make -f Makefile.linux-aarch64 SYSROOT=/tmp/jammy-sysroot   # with wrap env on PATH
# -> build/linux-aarch64/opt/squeezeplay/... tarred as squeezeplay-aarch64-9.0.0.tgz
```

Validate: `file` → ARM aarch64; `readelf -d` RUNPATH exactly
`/opt/squeezeplay/lib`; `readelf -V` sweep max GLIBC_2.34, zero
`__isoc23`; `qemu-aarch64` boots jive to the main loop and loads 10/10
Lua modules. Evidence + exact probe commands:
[test-results/diag-jammy-build.md](test-results/diag-jammy-build.md).

### 1c. fbcon libSDL (stock kernel has fb0, no DRI)

Source: pristine `SDL-1.2.15` from the pinned squeezeplay tree above
(`/tmp/jammy-sp/squeezeplay/src/SDL-1.2.15`), `make distclean` first.
With the Jammy wrap env active (`CC/CXX` from it):

```sh
CFLAGS="-march=armv8-a+crc -mtune=cortex-a53 -O2 -fPIC" \
./configure --host=aarch64-linux-gnu --prefix=/tmp/sdl-fbcon/out \
  --enable-video-fbcon --disable-video-x11 --disable-video-directfb \
  --disable-video-svga --disable-video-photon --disable-video-qtopia \
  --disable-audio --disable-joystick --disable-cdrom --disable-assembly
make -j"$(nproc)" && make install
# -> /tmp/sdl-fbcon/out/lib/libSDL-1.2.so.0.11.4 (302696 B)
```

Validate: aarch64, NEEDED libm+libc only, max GLIBC_2.34, bootstrap
registers exactly `dummy` + `fbcon`. Evidence:
[test-results/sdl-fbcon-build.md](test-results/sdl-fbcon-build.md).
It shadows the tarball's dummy-video libSDL at runtime via
`LD_LIBRARY_PATH` (same SONAME) — never overwrite the tarball copy.

## 2. Small inputs (in git or one-liners)

| Input | Source | Notes |
|---|---|---|
| `stock/compat/sysv_shim.so` | `stock/compat/sysv_shim.c` — **not in git** (`*.so` ignored) | SysV→POSIX SHM+sem for the `SYSVIPC=n` kernel. Build **on the device**: `gcc -shared -fPIC -O2 -o sysv_shim.so sysv_shim.c`, copy to `stock/compat/`. Must exist before packing (`pack.sh` refuses without it). Max GLIBC_2.34. |
| `stock/compat/evdev2jive-stock` | committed aarch64 binary + `ui/input/evdev2jive.c` | evdev→uinput mapper. Rebuild on device: `gcc -std=c99 -Wall -Wextra -O2 -o evdev2jive-stock ui/input/evdev2jive.c`. Map: `ui/input/rg35xxh-stock.map`. |
| Skins | `ui/skins/RG35XXH{Base,Landscape}Skin` (committed, generated) | Regenerate deterministically, must be a no-op: `ui/skins/scale_qvga_2x.py --src /tmp/squeezeplay --out ui/skins` then `git status` clean. |
| BSP applet | `squeezeplay/configuration/rg35xxh_bsp/` | platform applet + home-item wiring, overlaid by pack. |
| Identity patch | `stock/bundle/rg35xxh-identity.patch` | machine/skin/applet-query, applied by pack. |

## 3. Pack

```sh
squeezebox-go/pack.sh --output /tmp/sbgo-dist
# -> /tmp/sbgo-dist/SqueezeboxGo-<ver>-stockos-rg35xxh.zip (+ .sha256)
```

- Version comes from `squeezebox-go/VERSION`. Override inputs:
  `--jammy-tarball PATH --fbcon-lib PATH` (defaults: the §1 paths).
- `--fixture` builds a tiny synthetic payload (for CI-less hosts and
  the reproducibility test); `--epoch E` pins mtimes (default:
  `SOURCE_DATE_EPOCH` or HEAD commit time).
- The packer prints input SHAs — compare with the provenance line at
  the top of this guide when bisecting a bad build.
- The icon is generated at pack time (`icon/make-icon.py`, 240x180
  RGBA, device-verified); git stays text-only.

## 4. Gates (all must pass before any release)

```sh
bash tests/selftest.sh                    # 27/27 project selftest
bash squeezebox-go/tests/test-package.sh  # 131/131 incl. fixture-ZIP build
bash stock/tests/test-rg35xxh-identity.sh # identity patch + applet fallback
bash stock/tests/test-sysv-shim.sh        # shim host build + behavior
bash ui/input/tests/run_tests.sh          # 16/16 mapper maps
bash tests/run_shellcheck.sh              # shell lint (syntax fallback)
lua5.1 standalone/patches/standaloneradio-local-nowplaying/test-local-player-status.lua  # 30/30
```

## 5. Deploy to the device

```sh
scp /tmp/sbgo-dist/SqueezeboxGo-<ver>-stockos-rg35xxh.zip rg35xxh:/tmp/sbgo.zip
ssh rg35xxh 'sudo -n unzip -o -q /tmp/sbgo.zip -d /mnt/mmc/Roms/ \
  && cat /mnt/mmc/Roms/APPS/SqueezeboxGo/VERSION'
# then on the handheld: App Center -> SqueezeboxGo (entry auto-upgrades,
# preserving /opt/squeezebox-go/config).
```

SSH setup: [SETUP.md](SETUP.md). Logs on device (RAM):
`/dev/shm/squeezebox-go/logs/` (`launch-*.log`, `jive.log`,
`restore.log`); persistent `/opt/squeezebox-go/install.log`.
User-facing install/upgrade/troubleshooting:
[squeezebox-go/INSTALL.md](../squeezebox-go/INSTALL.md).

Fast iteration (entry/launch-only changes): `scp` the file straight
to `/opt/squeezebox-go/` and relaunch from App Center — no repack.
Full pack for anything under `jive/`, skins, or version bumps.

## 6. Reproducibility

Fixed mtime (`--epoch`), sorted entries, fixed uid/gid/modes,
`gzip -n`. Proof: `test-package.sh` builds the fixture ZIP twice and
`cmp`s the bytes. To compare two device builds, diff the `MANIFEST`
(input SHAs) before diffing bytes.

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `GLIBC_2.38 not found` on device | tree built against noble headers; rebuild §1 against the Jammy sysroot (wrappers, not bare `--sysroot`) |
| `__isoc23_*` undefined refs at link | noble 2.39 headers leaked in; re-check `-isystem` order (multiarch dir first) |
| Entry `payload hash mismatch` | bad copy to FAT; re-copy the ZIP, verify `.sha256`, re-launch |
| Stuck at App Center Loading | fixed in 0.2.9+ (entry tap-bounce re-arms scanout); older: remote `fb-preset.py` cycle |
| 512x384 / stride garbage | a non-RG35XXH skin set a foreign video mode; only RG35XXH 640x480 skins work — restart recovers (setting stays Landscape) |
| Black home screen | no wallpaper setting (pre-0.2.10 seeds); Settings → Wallpaper, or upgrade |
| `applet query` shows no rg35xxh entries | server lacks the target; installer falls back to `baby` (pure-Lua applets run) |
| No sound / device busy | another PCM holder; launch log names frontend state; `plughw:audiocodec` is the device |
