# WP1 UI validation record (Agent 4, branch `wp1/ui`)

Date: 2026-11-15. Host: x86_64 Ubuntu 24.04, gcc 13.3, Lua 5.1.5
(PUC-Rio, same major as target), python 3.12. All commands run from the
`wp1/ui` worktree; pinned sources fetched to `/tmp` (never into git).

Owner note: this file lives in Agent 6's tree (`docs/test-results/`) at the
Workflow owner's direction ("record under docs/test-results/wp1-ui.md");
code changes are confined to `ui/`.

## 1. Graphics backend + vendor pin

- `ui/vendor/fetch-sdl12-compat.sh`: downloads
  `release-1.2.78` tarball, `sha256sum -c` PASS
  (`40ec5f0b…da11a`, commit `07043bdcfd0d16ea8f14fe2a375089d00566a5e9`).
- Key-translation claims in `ui/README.md` verified by reading
  `Keysym20to12()` / `SDL_EnableUNICODE` / repeat synthesis in the
  extracted `release-1.2.78` source (no SDL2-audio mapping; SDL2 repeats
  dropped; `unicode` filled from text input).
- Jive-side claims verified in `squeezeplay@758bc11`:
  `SDL_EnableKeyRepeat(500,100)` + `SDL_EnableUNICODE(1)`
  (`jive_framework.c`), `charActionMappings` (`InputToActionMap.lua`),
  `pause`=`togglePause`, `jump_rew/fwd`=`rew()/fwd()` (SlimBrowserApplet).

## 2. Skin (`ui/skins/`)

- Generator: `scale_qvga_2x.py --src /tmp/squeezeplay@758bc11 --out` →
  `lua=4 img=467 bytes_in=6854971 bytes_out=8499313`.
- Determinism: re-ran into a fresh dir, `diff -r` vs committed skin =
  identical (only stale `.gitkeep`, since removed).
- `luac -p` (5.1.5): all 4 generated lua files PASS.
- Differential literal audit (every source number re-lexed, scaled-vs-kept
  checked): base 669 numbers (585 scaled, 26 kept), landscape 147 numbers
  (97 scaled, 28 kept), **0 errors**. Kept values are exactly the audited
  set: `hidden/horizontal/zOrder/frameRate/TRACKINFO_LINES`, `setVideoMode`
  bpp 16, `*`/`/` operands, hex colors. Spot-checked: 640/480 defaults,
  `artworkSize 640x640/286x286`, `registerSkin`, imgpaths.
- PNGs: all 467 decode; dimensions exactly 2x source; format/bitdepth
  preserved (incl. one 16-bit RGBA); `file` reports
  e.g. `PNG image data, 640 x 480, 8-bit/color RGB, non-interlaced`;
  6-image pixel round-trip PASS.
- No Jive render test on host (needs full aarch64 build) → WP2 item.

## 3. Input (`ui/input/`)

- `tests/run_tests.sh`: native `gcc -std=c99 -Wall -Wextra` build with
  **zero warnings**, then **pass=13 fail=0**: 10 recorded `--test` replays
  (hold+debounced release, short tap, tap auto-release, long-press on tap
  and hold keys, bounce collapse, axis press/release/flip with hysteresis,
  multi-key + unmapped drop, kernel-repeat ignore, volume hold) diffed
  against hand-computed expected outputs, plus 3 bad-map rejections
  (unknown code, duplicate input, release>=press).
- `--dump-map rg35xxh.map`: 19 keys + 4 axes parse; input codes match
  mainline DTS (`BTN_EAST/SOUTH/…`, `ABS_{X,Y,RX,RY}`); adc-joystick
  inverted-range handling read in `adc-joystick.c` (driver-compensated).
- Live uinput/evdev path compiles but needs hardware or root+uinput → WP2.

## 4. Splash (`ui/splash/`)

- `make_splash.py`: writes 640x480 8-bit RGB PNG (2824 bytes,
  sha256 `bdd88f08…b4cd`); `file` confirms format; regen `cmp` identical
  (deterministic); ASCII-raster check reads `SQUEEZEBOX` / `RG35XX H` /
  `SQUEEZEPLAY 8.0` correctly.
- `test_splash` (pngmini+blit, `-Wall -Wextra`, zero warnings):
  **ALL PASS** — decode dims/comp, gradient corners, 10688 bright headline
  pixels, garbage/truncation rejection, 1:1 blit pixels, 800x600 letterbox
  centering, RGBA composite math (`0x800000`).
- `drm_splash.c` builds warning-free against host kernel UAPI headers
  (raw ioctls, no libdrm); error paths exercised (bad card → exit 1 with
  message, bad flag → usage exit 2). Live paint needs `/dev/dri` → WP2.
- `init-splash.sh`: `sh -n` PASS; host run shows graceful
  no-backend failure (exit 1), clean stop (exit 0), usage error (exit 2).
  (`shellcheck` not installed on host — not run.)

## Not run (need target/hardware)

Physical RG35XX H checks: SDL2/KMSDRM first frame, skin render, evtest
direction/`flip` confirmation, uinput→SDL→Jive end-to-end keys, volume
repeat feel, DRM splash on panel, boot ordering with squeezeplay.service.
