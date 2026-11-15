# UI — graphics backend, skin, input, splash (Agent 4)

## 1. Graphics-backend decision (WP1)

**Decision: SDL 1.2 API via sdl12-compat (built from source) on SDL2/KMSDRM,
X-less, direct DRM/KMS + Panfrost GLES.** No fbdev, no X11, no desktop.

Rationale and evidence:

- SqueezePlay (`ralph-irving/squeezeplay@758bc11`) targets the SDL 1.2 API
  (`SDL_SetVideoMode`, software surfaces, `SDL_EnableKeyRepeat/UNICODE`).
  Rewriting it to SDL2 is out of scope; sdl12-compat is the upstream-blessed
  shim (same project, same authors as SDL2) and preserves the exact 1.2 event
  semantics Jive relies on (key repeat synthesis, unicode, scancodes).
- The H700 target stack is mainline kernel + Panfrost (Mali-G31) + a KMS LCD
  panel carried out-of-tree (ADR-0001). SDL2's `kmsdrm` video driver plus
  `libinput` keyboard is the maintained X-less path; SDL 1.2's own backends
  (fbcon, directfb, X11) are dead ends on this SoC.
- Verified in the pinned sources (`/tmp` ref checkouts, WP1):
  - `sdl12-compat@release-1.2.78`: `Keysym20to12()` forwards arrows,
    Enter/Return, Home/End, Menu, PageUp/Down, Print, F1–F15, Power; SDL2
    audio keycodes map to `SDLK_UNKNOWN` (no media-key translation).
    SDL2-style repeats are dropped and SDL1.2-style repeats are synthesized
    from the app's `SDL_EnableKeyRepeat()` settings — which Jive sets
    (`jive_framework.c`: `SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY, 100)`).
    `SDL_EnableUNICODE(1)` (also set by Jive) is honored: `keysym.unicode`
    is filled from SDL2 text input. Our whole input map (`ui/input/`) is
    designed around exactly these three behaviors.
  - Jive consumes plain characters via `JIVE_EVENT_CHAR_PRESS` and Lua
    `charActionMappings` (`share/jive/InputToActionMap.lua`), so transport
    buttons need no patched SDL and no framework patch.

Pin: `ui/vendor/sdl12-compat.pin` (`release-1.2.78`,
commit `07043bdcfd0d16ea8f14fe2a375089d00566a5e9`, sha256-verified tarball).
Fetch (outside git): `ui/vendor/fetch-sdl12-compat.sh [DESTDIR]`.

SDL2 itself is owned by Agent 2 (toolchain). Requirement from UI side:
SDL2 ≥ 2.30 with `kmsdrm` video + `libinput` input + `xkbcommon` (reference:
upstream tag `release-2.32.10`). KMSDRM without libinput has no keyboard.

## 2. Build notes (for Agent 2 / image build)

sdl12-compat build (CMake, needs SDL2 target headers):

```sh
SRC=$(./ui/vendor/fetch-sdl12-compat.sh)
cmake -S "$SRC" -B build-compat \
  -DCMAKE_TOOLCHAIN_FILE="$SYSROOT_TOOLCHAIN" \
  -DSDL2_INCLUDE_DIR="$SYSROOT/opt/sdl2/include/SDL2" \
  -DSDL12TESTS=OFF -DSDL12DEVEL=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-compat
# installs: libSDL-1.2.so.0 (the compat shim) + SDL 1.2 headers
```

- SqueezePlay then builds against the compat headers/libs exactly as if SDL
  1.2 were present (`sdl-config --cflags/--libs` from the install prefix).
- Link order: `libSDL-1.2(compat)` → `libSDL2` → `libdrm`, `libinput`,
  `libxkbcommon`, `libudev`, GLES (Panfrost `libGLESv2`).
- Do NOT build the vendored `src/SDL-1.2.15` tree for the target; it is
  reference only (its patched `SDL_keysym.h` documents the MCE media-key
  values, intentionally unused — see `ui/input/README.md`).

Runtime environment (image / `squeezeplay.sh`):

```sh
export SDL_VIDEODRIVER=kmsdrm
export SDL_RENDER_DRIVER=opengles2   # Panfrost; fallback: software
export SDL_KMSDRM_ORIENTATION=0
export JIVE_FRAMERATE=30             # 4..60, parsed by jive_frame_rate()
```

Jive calls `SDL_SetVideoMode(640, 480, 16, fullscreen)` from the skin; the
compat layer upscales/centers per `SDL12COMPAT_*` defaults (no override needed
at 1:1). LCD is 640x480, so this is a 1:1 mode — no scaler blur.

## 3. Layout

- `ui/skins/` — `RG35XXHBaseSkin` + `RG35XXHLandscapeSkin` (committed 2x
  bootstrap of the QVGA Radio skin) and the `scale_qvga_2x.py` generator.
- `ui/input/` — `evdev2jive` daemon + `rg35xxh.map` (contract input map).
- `ui/splash/` — boot splash PNG, generator, DRM viewer, init script.
- `ui/vendor/` — sdl12-compat pin + fetch script (no vendored trees in git).
- `ui/install.sh` — DESTDIR-style staging of skins, fonts, mapper, splash
  into a rootfs overlay dir (writes a sha256 manifest, self-checks).
- `ui/tests/sdl_smoke.c` — minimal SDL 1.2 init/mode/flip smoke test.
- `ui/BRINGUP.md` — target bring-up runbook (splash order, KMS first
  frame, skin render, evtest, uinput E2E) + cross-build appendix.
