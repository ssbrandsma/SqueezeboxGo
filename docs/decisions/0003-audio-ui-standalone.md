# ADR-0003 — Audio, UI/input, Standalone scope

Date: 2026-11-15. Status: accepted.

## Audio

- ALSA throughout (`decode_alsa.c` + `decode_alsa_backend.c` from sp tree).
- Internal sun4i-codec default; `snd-usb-audio` optional; single-owner arbiter
  (`audio-owner acquire|release`), no concurrent opens, crash-safe release.
- EDO repo deferred until vendored and verified; no x86 binaries on ARM64.
- Bit-perfect claims only after full decoder→device validation.

## UI / input

- SDL 1.2 API via sdl12-compat (built from source) on SDL2/KMSDRM, X-less,
  direct DRM/KMS + Panfrost GLES. No fbdev/X11/desktop.
- Custom 640x480 skin = 2x integer scale of QVGA Radio skin (pixel-perfect start).
- evdev→SDL-keyboard mapper per `interface-contracts.md`; no touchscreen.
- Boot splash: lightweight DRM/PNG init splash; hook into image boot chain.

## Standalone

- All 11 ecosystem components missing from workspace; Baby/Fab4 deps unknown.
- Rule: no invented APIs. WP1/WP3 build integration framework + adapters from
  real sources only; Agent 5 documents exact required repos/versions.
- TinySC/TinyLMS forbidden as runtime foundation; LMS stays optional via SlimProto.
