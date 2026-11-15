# Sysroot notes (WP1 Core)

## Where target headers/libs come from

The cross build needs exactly one target dependency outside the vendored
`squeezeplay/src` tree: **ALSA** (`alsa/asoundlib.h`, `-lasound`), used by
Jive's own audio backend (`decode_alsa.c`, `decode_alsa_backend.c`).
Everything else (SDL, Lua, codecs, freetype, …) is built from the vendored
tree into the staging prefix. SDL audio is disabled; Jive never uses it.

| Environment | aarch64 sysroot provider |
|---|---|
| Pinned container (`Dockerfile`) | `libasound2-dev:arm64` (+ `libc6-dev-arm64-cross`), found via the cross-gcc default search paths (`/usr/aarch64-linux-gnu`) — `SYSROOT=/` |
| Debian/Ubuntu host with cross toolchain | `apt install gcc-aarch64-linux-gnu libasound2-dev:arm64` — `SYSROOT=/` |
| Custom sysroot (firmware rootfs) | unpack target rootfs; pass `SYSROOT=<dir>` so `--sysroot=<dir>` is added to `CFLAGS`/`LDFLAGS` |

`make -f Makefile.linux-aarch64` fails fast (`check-deps`) when
`alsa/asoundlib.h` is not usable by `$(CC) $(CFLAGS)`.

## Why `--sysroot` handling is explicit

Debian cross-gcc already targets `/usr/aarch64-linux-gnu`, so the default
`SYSROOT=/` adds no flag. Firmware sysroots (Agent 1 rootfs) relocate libc
and ALSA; `SYSROOT=<dir>` then redirects both compile and link. Every
hand-rolled Lua module makefile receives the flags explicitly (see the
`WARN=`/`CFLAGS=`/`G=`/`MYLDFLAGS=` injections in
`squeezeplay/configuration/Makefile.linux-aarch64`), because those files
hardcode their own flag variables.

## Validating outputs (build contract gates)

```sh
file <staging>/opt/squeezeplay/bin/jive* squeezeplay-*.tgz
readelf -d <staging>/opt/squeezeplay/bin/jive | grep -E 'NEEDED|RPATH|RUNPATH'
find <staging>/opt/squeezeplay/lib -name '*.so*' | sort   # == .so-list.txt
```

Expected: `ELF 64-bit LSB executable/shared object, ARM aarch64`,
`NEEDED libasound.so.2` (+ libc/m/pthread/dl), `RPATH/RUNPATH
/opt/squeezeplay/lib`. Ubuntu-built ARM64 artifacts must be re-validated
against the firmware sysroot before they ship in the image (see
`docs/build.md`).

## Custom / rootless sysroots (proven 2026-11-15)

The WP1 cross build was validated with a rootless sysroot assembled from
`apt-get install --download-only` cross-toolchain debs + arm64 `libasound2*`
and `libc6` debs from `ports.ubuntu.com`, extracted to one prefix and used
with `SYSROOT=<prefix>`. Three gotchas, all with working fixes:

1. **Old libtool drops `--sysroot`.** expat/freetype/SDL ship libtool
   1.5.x, which silently drops `--sysroot=` from link lines (verified by
   `libtool -n --mode=link` dry-run). Fix: shadow the cross compiler
   earlier in `PATH` with a wrapper that always appends the sysroot:
   `exec /real/aarch64-linux-gnu-gcc --sysroot=<prefix> "$@"`
   (same for `g++`). Not needed in the container (`SYSROOT=/`).
2. **`-rpath-link` is mandatory under `--sysroot`.** With a sysroot, `-L`
   works for direct `-l` flags but not for the transitive DT_NEEDED chase
   (`libz.so.1 ... not found (try using -rpath or -rpath-link)`).
   `Makefile.linux-aarch64` therefore always passes
   `-Wl,-rpath-link -Wl,$(SPREFIX)/lib` (split form: libtool 1.5 mangles
   the 3-part `-Wl,-rpath-link,<dir>` variant).
3. **Relocated Debian sysroots need `=`-prefixed linker scripts.** The
   `libc.so`/`libm.so` GROUP paths (`/usr/aarch64-linux-gnu/lib/...`) are
   absolute; prefix each with `=` (`=/usr/...`) so `ld` resolves them
   under `--sysroot`.

## Not in the sysroot (by design)

- X11 headers: SDL is configured `--enable-video-x11=no`.
- readline/ncurses: Lua patch 0001 drops the dependency.
- tslib: no touchscreen on this device.
- scons: tolua++ runtime lib is compiled directly (tcz-style).
- Java/Python codegen at build time: the shipped `lua_jiveui.c` is reused
  (bindings untouched); no host `tolua++` binary required.
