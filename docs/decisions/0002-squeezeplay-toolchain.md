# ADR-0002 — SqueezePlay baseline + ARM64 toolchain

Date: 2026-11-15. Status: accepted.

## Context

Two candidate trees: `ralph-irving/squeezeplay` (desktop) vs
`ralph-irving/squeezeos-squeezeplay` (firmware). Need ARM64 + Lua + SlimProto.

## Evidence

- `squeezeplay@758bc11`: modern base (SDL-1.2.15, lua-5.1.5, jpeg-9d),
  ALSA backend with S32/S24/S16 fallback + hi-res fixes, UTMAC/SIGTERM/glibc
  improvements, M1 arm64 build proof. 32 C files newer than sos tree.
- `squeezeos-squeezeplay@766b6a8`: pins arm-926ejs/gcc-4.1.1, SDL-1.2.13,
  lua-5.1.1, axTLS-1.2.0. SlimProto delta is 1 line (Balance cap).
- aarch64 recipe exists only for jivelite (`tcz-jivelite` 184-line patch,
  `Makefile.picoreplayer-aarch64`, cortex-a72 flags, PUC-lua, PREFIX+rpath).
- No full-UI aarch64-linux squeezeplay makefile exists upstream.

## Decision

- Baseline: `squeezeplay@758bc11`; reference `squeezelite@cc7ee7c`
  (slimproto/output_alsa); recipe `jivelite@d43a20b`+`tcz-jivelite@4bdf677`;
  sos tree backports only.
- Toolchain: `-march=armv8-a+crc -mtune=cortex-a53` (retuned for H700),
  PUC lua-5.1.5 shared-lib, `PREFIX=/opt/squeezeplay`.
- WP1 creates `Makefile.linux-aarch64` + `rg35xxh_bsp` (cloned from fab4 pattern).
