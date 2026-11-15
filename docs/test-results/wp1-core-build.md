# WP1 Core build report (Agent 2)

Date: 2026-11-15. Branch: `wp1/core`. Baseline: squeezeplay@758bc11.
Owner note: written by Agent 2 on Lead instruction (WP1 task plan);
`docs/test-results/` is Agent 6's tree — coordinate on format changes.

## Result

- **aarch64 cross build: PASS** (exit 0), full chain SDL → Lua → codecs →
  Jive core → tarball, after 5 build-system fixes (all committed).
- **Native x86_64 validation build: PASS** (exit 0), from scratch.
- **aarch64 boot under qemu-user: PASS** — `jive` reaches the main loop
  (`SqueezePlay version 9.0.0 r541`, skin select, applets, settings writes).

## Exact build commands (handoff)

Prerequisites: pinned container (`build/toolchain/Dockerfile`) or an
equivalent cross toolchain + arm64 ALSA. Fetch + patch:

```sh
git clone https://github.com/ralph-irving/squeezeplay && cd squeezeplay
git checkout 758bc110e16de4a61905e19d012a0ad25d97859b
cp <tree>/squeezeplay/configuration/Makefile.linux-aarch64 src/
for p in <tree>/squeezeplay/patches/000*.patch; do patch -p1 < "$p"; done
```

Cross (target) build:

```sh
cd src && make -f Makefile.linux-aarch64   # SYSROOT=/ in the container
```

Native validation build (needs `build/toolchain/build-native-deps.sh` once):

```sh
eval "$(build/toolchain/build-native-deps.sh --env --prefix <dir>)"
cd src && make -f Makefile.linux-aarch64 CROSS_COMPILE= \
  ARCHFLAGS="-march=x86-64" LUA_ARCHFLAGS="-s -O2"
```

Outputs: `<build>/linux-aarch64/opt/squeezeplay/` staging tree,
`squeezeplay-aarch64-9.0.0.tgz` + `.sha256` + `.so-list.txt` next to `src/`.

## Validation evidence (cross/aarch64)

- `file bin/jive bin/jive_alsa bin/lua lib/liblua.so lib/lua/5.1/socket/core.so`:
  all `ELF 64-bit LSB, ARM aarch64` (libSDL-1.2.so.0 is a symlink).
- `readelf -d bin/jive`: NEEDED libtolua++.so, SDL_image/ttf/gfx, FLAC, mad,
  vorbisidec, fdk-aac, lua, m, SDL-1.2, c (+ld-linux); `RUNPATH
  [/opt/squeezeplay/lib]` exactly — no staging leakage.
- `readelf -d bin/jive_alsa`: NEEDED libm, **libasound.so.2**, libc.
  (`jive` itself correctly has no libasound: `decode_alsa.c` makes no
  `snd_*` calls — it fork+execs `jive_alsa`. Ship both binaries.)
- 245 compile lines carry `-march=armv8-a+crc -mtune=cortex-a53`.
- `version.h`: `SQUEEZEPLAY_RELEASE "9.0.0"`, `SQUEEZEPLAY_REVISION "541"`
  (git revcount via patch 0002).
- qemu-user (`-L` merged sysroot + `LD_LIBRARY_PATH=/opt/squeezeplay/lib`
  as `squeezeplay.sh` sets): `lua` runs; `cjson socket.core lxp lfs
  mime.core md5 zipfilter` all load; full `jive` boot to main loop with
  skin select + applet registration + settings writes (timeout kill = alive;
  `WQVGAsmallSkin` desktop default — device skin is Agent 4).
- Tarball: `squeezeplay-aarch64-9.0.0.tgz`, 23535890 bytes,
  sha256 `efe42717d8c1d21cc44fbbd219a9451dfcf8088e27f139b54039c324c8ad954a`.

## Fixes made during the build (all in-tree)

1. Scrub staging `*.la` before the Jive link/packaging (installed `.la`
   files embed final-prefix `/opt/...` paths that break libtool).
2. Patch 0003: link `jive`/`jive_alsa` with `-lm` (modern-ld `DSO missing`).
3. Export `CXX` (fdk-aac has C++ objects) + `check-deps` covers it.
4. `LDFLAGS` gains `-Wl,-rpath-link -Wl,$(SPREFIX)/lib` (split form:
   under `--sysroot`, `-L` is not used for transitive DT_NEEDED;
   libtool 1.5 mangles the 3-part `-Wl` spelling).
5. SDL configured without X11/tslib/audio (headers+ABI only; runtime video
   via Agent 4's sdl12-compat); tolua bindings use shipped `lua_jiveui.c`.

## Known non-defects / notes for other agents

- Headless boot needs a video driver reporting nonzero dimensions (SDL dummy
  reports 0x0 → `exit(-1)`); Jive log categories default to OFF, so such
  failures are silent unless `logconf.lua` enables them (Agent 6: ship a
  default logconf on the image; Agent 4: KMS driver reports 640x480).
- No `jive/splash640x480.png` upstream → falls back to `splash.png`
  (Agent 4 splash work).
- `start_demo` action unregistered warning is pre-existing upstream.
- **Lead decision needed:** build contract says `JIVE_VERSION=8.0.0-r<N>`
  but the pinned tree's `squeezeplay.version` is `9.0.0`; this build ships
  truthful `9.0.0 r541`. Override knob exists
  (`SQUEEZEPLAY_RELEASE=8.0.0 make ...`) if 8.0.0 is required.

## .so list for audio/UI agents (aarch64 staging, 60 entries)

Runtime link libs (`/opt/squeezeplay/lib/`): libFLAC.so.8, libSDL-1.2.so.0,
libSDL_gfx.so.0, libSDL_image-1.2.so.0, libSDL_ttf-2.0.so.0, libexpat.so.1,
libfdk-aac.so.2, libfreetype.so.6, libjpeg.so.9, liblua.so, libmad.so.0,
libogg.so.0, libpng12.so.0 (+libpng.so.3 compat), libtolua++.so,
libvorbisidec.so.1, libz.so.1 (plus unversioned `.so` dev symlinks).

Lua 5.1 modules (`lib/lua/5.1/`): cjson.so, lfs.so, lxp.so, md5.so,
mime/core.so, profiler.so, rtmp.so, sha1.so, socket/core.so,
unicode/core.so, zipfilter.so (+ `share/lua/5.1/loop/*`, socket/mime
Lua sources).

Full 60-line list: build artifact `squeezeplay-aarch64-9.0.0.so-list.txt`.
Logs: `/tmp/wp1-core/cross-build7.log` (cross, exit 0),
`/tmp/wp1-core/final-native.log` (native, exit 0) — both on the WP1 host.
