# SDL 1.2 fbcon build for stock PoC (Lead-built, 2026-11-16)

Why: stock kernel 4.9.170 has `/dev/fb0` but no `/dev/dri`, so our
sdl12-compat/SDL2-KMSDRM stack cannot work there. The stock PoC needs a
framebuffer-backed SDL 1.2. dmenu.bin proves the route (32-bit armhf,
SDL1.2-fbcon, visible on the LCD).

## Recipe (all observed)

- Source: pristine copy of `SDL-1.2.15` from the pinned squeezeplay tree
  (`/tmp/jammy-sp/squeezeplay/src/SDL-1.2.15`), `make distclean` first.
- Toolchain: Jammy sysroot recipe (`build/toolchain/jammy-sysroot.sh`):
  existing `/tmp/jammy-sysroot` + `/tmp/jammy-wrap` re-verified with
  `--check` (probe max GLIBC_2.34) after `eval --env`. (A fresh prefix
  fails: no g++ on PATH and /tmp/x-tools partially cleaned — reuse the
  proven prefix + wrappers, do not rebuild from scratch without a toolchain.)
- Configure:
  `CC/CXX` from wrap env, `CFLAGS="-march=armv8-a+crc -mtune=cortex-a53 -O2 -fPIC"`,
  `./configure --host=aarch64-linux-gnu --prefix=/tmp/sdl-fbcon/out --enable-video-fbcon --disable-video-x11 --disable-video-directfb --disable-video-svga --disable-video-photon --disable-video-qtopia --disable-audio --disable-joystick --disable-cdrom --disable-assembly`
- `make -j$(nproc)` exit 0, `make install` exit 0.

## Validation (all observed)

- `libSDL-1.2.so.0.11.4` (302696 B):
  sha256 `3924a6254c1c4c9690b7d7f3905465b84f7dd134b372155909eca02d6f3f8d4a`
- `file` → ELF 64-bit ARM aarch64; NEEDED libm + libc only (no X11).
- Max GLIBC_2.34 → runs on Jammy 2.35. Zero `__isoc23` (same class as
  the Jammy jive build; ALSA untouched — SDL audio disabled by design).
- fbcon proven IN: `SDL_VIDEO_DRIVER_FBCON 1` in config header, bootstrap
  registers exactly `dummy` + `fbcon`, 48 `FB_` symbols in libSDL.a.

## Deploy notes (for the hardware agent)

- Artifact: `/tmp/sdl-fbcon/out/lib/libSDL-1.2.so.0.11.4` (+ `.so.0` link).
- It shadows the Jammy tarball's dummy-video libSDL at runtime via
  `LD_LIBRARY_PATH` (same SONAME `libSDL-1.2.so.0`) — never overwrite the
  tarball copy; keep both and select by path.
- Open risk: fb0 writes are proven writable but NOT proven visible (DE
  scans a 640x480 layer; fb0 is 1280x1024) — the human red-fill look
  decides before any "video works" claim.
