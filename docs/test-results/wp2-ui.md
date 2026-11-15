# WP2 UI validation record (branch `wp2/ui`)

Date: 2026-11-15. Host: x86_64 Ubuntu 24.04, gcc 13.3, python 3.12,
qemu-aarch64 8.2.2. Code commit: `c327df4`
(`[ui] WP2 first-boot integration: install.sh overlay staging,
sdl_smoke, BRINGUP runbook`).

Owner note: this file lives in Agent 6's tree (`docs/test-results/`)
at the Workflow owner's direction ("Evidence:
docs/test-results/wp2-ui.md"); code changes are confined to `ui/`.

## 0. Scope

WP2 UI tasks: (1) cross-build sdl12-compat (pinned) + evdev2jive +
drm_splash for aarch64 with arch verification, plus native host
builds; (2) skin+font+mapper install layout (`ui/install.sh`,
DESTDIR-style overlay staging); (3) headless smoke (evdev2jive unit
tests, splash regen-identity, minimal SDL init); (4) target bring-up
runbook (`ui/BRINGUP.md`). All four complete; hardware-dependent
steps remain NOT RUN (no RG35XX H on hand).

## 1. Toolchain (rootless, reproducible)

No container runtime is available inside this sandbox and no system
cross toolchain is installed, so the WP1-documented rootless recipe
(`build/toolchain/sysroot-notes.md`) was used: noble archive debs
downloaded with `apt-get install --download-only` (custom
`Dir::Cache`, `Debug::NoLocking`) and extracted with `dpkg-deb -x`
to `/tmp/wp2-ui/tc` (never installed); arm64 zlib debs fetched from
`ports.ubuntu.com` by pool path from the arm64 `Packages` index.

- Cross: `gcc-aarch64-linux-gnu 4:13.2.0-7ubuntu1` (gcc 13.3.0),
  `binutils-aarch64-linux-gnu 2.42-4ubuntu2.10`,
  `libc6-dev-arm64-cross 2.39-0ubuntu8cross1`,
  `linux-libc-dev-arm64-cross 6.8.0-25.25cross1`,
  `zlib1g(_-dev) 1:1.3.dfsg-3.1ubuntu2` (arm64).
- Build tools: cmake 3.28.3 (deb, extracted rootless).
- Use: `--sysroot=$TC` on every compile/link,
  `LD_LIBRARY_PATH=$TC/usr/lib/x86_64-linux-gnu` (cross binutils
  shared libs), contract flags
  `-march=armv8-a+crc -mtune=cortex-a53 -O2`.
- Toolchain smoke: hello-world links and `file` reports
  `ELF 64-bit LSB pie executable, ARM aarch64`.

In the pinned container (`build/toolchain/Dockerfile`) the identical
build commands run with plain `aarch64-linux-gnu-gcc` and no
`--sysroot` (see `ui/BRINGUP.md` appendix A).

## 2. aarch64 cross builds (all `file` → ARM aarch64)

| Artifact | Source | Result |
|---|---|---|
| `evdev2jive` | `ui/input/evdev2jive.c` (`-std=c99 -Wall -Wextra`) | exit 0, zero warnings |
| `drm_splash` | `drm_splash.c pngmini.c blit.c -lz` (same flags) | exit 0, zero warnings |
| `test_splash` | `test_splash.c pngmini.c blit.c -lz` (same flags) | exit 0, zero warnings |
| `libSDL2-2.0.so.0.3200.10` | SDL2 `release-2.32.10` tarball (sha256 `5f5993c5…a5165`), `--host=aarch64-linux-gnu`, contract `CFLAGS`, minimal fixture config (dummy/offscreen video; no x11/wayland/kmsdrm/gl/alsa/udev) | exit 0 |
| `libSDL-1.2.so.0` (1.2.78) | pinned `release-1.2.78` tarball, sha256-verified `40ec5f0b…da11a`; cmake + aarch64 toolchain file, `-DSDL12TESTS=OFF -DSDL12DEVEL=ON -DCMAKE_BUILD_TYPE=Release` | exit 0, no warnings/errors |
| `sdl_smoke` | `ui/tests/sdl_smoke.c` vs compat headers + both staging libs | exit 0, zero warnings |

`file` (all six): `ELF 64-bit LSB pie executable/shared object,
ARM aarch64`. `readelf -d`: evdev2jive NEEDED `libc.so.6` only;
drm_splash/test_splash `libz.so.1 + libc.so.6`;
`libSDL-1.2.so.1.2.78` SONAME `libSDL-1.2.so.0`, NEEDED libc only
(it `dlopen`s SDL2 at runtime — video-driver agnostic, so the
dummy-video fixture affects only the compat build, never target
behavior; the shipped kmsdrm+libinput SDL2 is Agent 2's
deliverable).

## 3. Headless smoke results

- evdev2jive native (`ui/input/tests/run_tests.sh`): build OK,
  **pass=13 fail=0** (10 `--test` replays + 3 bad-map rejections).
- evdev2jive aarch64 under `qemu-aarch64 -L $TC`: `--dump-map`
  parses `rg35xxh.map`; all 10 replay scripts byte-identical to
  `.expected` (**pass=10 fail=0**) — cross binary behaviorally
  identical to native.
- Splash regen: `make_splash.py` → 2824 bytes, `cmp` with committed
  `splash_640x480.png` identical (**REGEN-IDENTICAL**).
- `test_splash` native and aarch64-under-qemu: both `splash tests:
  ALL PASS` (10688 bright headline pixels both).
- `drm_splash` aarch64 under qemu: bad flag → usage, exit 2;
  missing card → `png: 640x480 comp=3` + clean `open ... No such
  file` message, exit 1. (Live `/dev/dri` paint needs hardware.)
- SDL smoke native (`SDL_VIDEODRIVER=dummy`, native SDL2 2.32.10 +
  native sdl12-compat 1.2.78): `SDL_Init: OK`, `video driver:
  dummy`, `SetVideoMode: OK 640x480 bpp=16`, `FillRect+Flip: OK`,
  `sdl_smoke: ALL PASS`, exit 0.
- SDL smoke aarch64 under qemu (aarch64 SDL2 fixture + aarch64
  compat): identical `ALL PASS`, exit 0 — the full SDL 1.2 API →
  compat → SDL2 chain verified on aarch64.
- `sh -n ui/install.sh`: PASS.

## 4. Install layout (`ui/install.sh`)

DESTDIR-style staging; verified with aarch64 `--bins` +
`--squeezeplay-src /tmp/wp2-ui/sq/src` (pinned squeezeplay
`758bc11`, fetched shallow, rev-parse confirmed):

- Full run: `install.sh: staged 479 files`, exit 0. Layout:
  `opt/squeezeplay/bin/{evdev2jive,drm_splash,init-splash.sh}`
  (0755, aarch64 ELFs), `etc/evdev2jive/rg35xxh.map`,
  `opt/squeezeplay/share/jive/applets/RG35XXH{Base,Landscape}Skin/`
  (Applet+Meta lua, `strings.txt` where present, 467 PNGs),
  `opt/squeezeplay/share/jive/fonts/FreeSans{,Bold}.ttf`
  (`cmp`-identical to squeezeplay `dejavu-fonts-ttf-2.37`
  `DejaVuSansCondensed{,-Bold}.ttf` — same rename rule as Agent 2's
  `freefont` target in `Makefile.linux-aarch64`),
  `usr/share/squeezebox/splash_640x480.png`,
  `opt/squeezeplay/share/squeezebox-ui-manifest.txt`.
- Manifest re-verification from the overlay root:
  `sha256sum -c` → **479 OK**, 0 failures.
- Variants: `--skin RG35XXHBaseSkin` stages one skin (307 files);
  no `--squeezeplay-src` skips fonts with a clear note (Agent 2
  installs identical bytes); missing `--destdir`/`--bins`/binary/
  font-src and bogus flags all exit 2 with a one-line reason.
- Font/shape ground truth inspected in the pinned tree:
  `Makefile.linux:287-288` + `Makefile.linux-aarch64:383-386`
  (DejaVu→FreeSans rename), `squeezeplay/share/applets/QVGAbaseSkin/`
  (Applet/Meta/images shape our skins mirror),
  `QVGAbaseSkinApplet.lua` (`FONT_NAME="FreeSans"`, `Font:load`
  from the fonts dir).

## 5. Bring-up runbook (`ui/BRINGUP.md`)

Covers, each with commands + expected output + fail paths: §0
overlay sanity (manifest re-check), §1 DRM splash ordering (early
paint, `ExecStartPre` handoff, stuck-splash debug), §2 KMS first
frame (`sdl_smoke` under `SDL_VIDEODRIVER=kmsdrm`, 640x480x16 +
blue frame), §3 skin render check (home menu, logconf caveat,
asset-error triage), §4 evtest direction confirm (DTS codes,
stick polarity, `flip` remedy), §5 uinput E2E table (every
control → uinput key → Jive action, doubles/stuck-key triage),
§6 re-staging reference, appendix A exact cross-build commands,
appendix B installed-layout reference.

## 6. Files changed (branch `wp2/ui`, commit `c327df4`)

- `ui/install.sh` (new, 0755) — overlay staging + manifest + checks.
- `ui/tests/sdl_smoke.c` (new) — SDL 1.2 smoke test.
- `ui/BRINGUP.md` (new) — target bring-up runbook.
- `ui/README.md` — layout index pointers to the above.
- This file (evidence; Agent 6 tree, Workflow-owner directed).

## 7. Not run (need target/hardware)

Physical RG35XX H checks from `ui/BRINGUP.md` §§1–5: real
`/dev/dri` splash paint + handoff timing, kmsdrm first frame on
panel, skin render in Jive, evtest code/polarity confirm, uinput →
SDL → Jive E2E feel. No block devices written; no images, secrets,
caches, or build outputs committed (all builds under `/tmp/wp2-ui`).
