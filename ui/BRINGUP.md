# UI target bring-up runbook (RG35XX H)

First-boot checks for the UI stack: boot splash → KMS first frame →
skin render → input end-to-end. Each step lists the command, the
expected result, and what to do when it fails. Assumes the WP2 image
is flashed and this tree's overlay (`ui/install.sh`, both skins,
`rg35xxh.map`, splash assets, aarch64 `evdev2jive` + `drm_splash`)
is on the rootfs. A serial console (or ssh) is required throughout.

Conventions: run on the **target** unless marked `[host]`.

## 0. Sanity: overlay present

```sh
ls /opt/squeezeplay/bin/evdev2jive /opt/squeezeplay/bin/drm_splash \
   /opt/squeezeplay/bin/init-splash.sh /etc/evdev2jive/rg35xxh.map \
   /opt/squeezeplay/share/jive/applets/RG35XXHBaseSkin/RG35XXHBaseSkinApplet.lua \
   /opt/squeezeplay/share/jive/fonts/FreeSans.ttf \
   /usr/share/squeezebox/splash_640x480.png
file /opt/squeezeplay/bin/evdev2jive   # ELF 64-bit LSB, ARM aarch64
(cd / && grep -v '^#' opt/squeezeplay/share/squeezebox-ui-manifest.txt \
  | sha256sum -c -) | grep -v ': OK$'  # empty = all intact
```

PASS: all paths exist, binaries are aarch64, manifest fully verifies.
FAIL: re-stage the overlay (`ui/install.sh --destdir`, see §6) and
re-flash / re-sync before continuing — later steps are meaningless
with a corrupt overlay.

## 1. DRM splash ordering (boot)

What should happen: ~1 s into boot the panel shows the static
`SQUEEZEBOX / RG35XX H` splash; it stays until Jive's first frame,
then hands DRM master to squeezeplay with at most one modeset flicker.

```sh
systemctl status splash.service          # active (exited), no errors
journalctl -b -u splash.service          # show ... stop, timestamps
dmesg | grep -i -E 'panel|drm.*fb|modeset' | head
```

On a fresh boot, watch the panel: splash visible early, then Jive UI.
Measure the handoff gap with the journal:

```sh
journalctl -b -o short-monotonic -u splash.service -u squeezeplay.service
```

PASS: splash painted before `squeezeplay.service` start; `init-splash.sh
stop` ran from `squeezeplay.service`'s `ExecStartPre`; no black screen
longer than ~1 modeset; if squeezeplay fails, the splash stays up
(preferred over black — see `ui/splash/SERVICE_HOOKS.md`).

FAIL paths:

- No splash, boot continues → `ConditionPathExists=/dev/dri/card0`
  unmet (panel/DRM not probed yet): check `ls /dev/dri`, DT panel
  nodes (Agent 1), `dmesg` for panel errors. Jive paints when it
  starts; splash absence alone never blocks boot by design.
- Splash never stops (stuck on splash) → squeezeplay failed to
  start: debug Jive (§3), then `init-splash.sh stop` by hand.
- Tearing/flicker at handoff → expected once (one modeset); repeated
  flicker means something else is also setting CRTCs — check for a
  second DRM master (`lsof /dev/dri/card0`).

## 2. KMS first frame (sdl_smoke)

Proves the SDL1.2→sdl12-compat→SDL2→kmsdrm chain on real hardware
before involving Jive. `sdl_smoke` (`ui/tests/sdl_smoke.c`) sets the
exact skin mode `SDL_SetVideoMode(640, 480, 16)`:

```sh
SDL_VIDEODRIVER=kmsdrm SDL_RENDER_DRIVER=opengles2 \
  /opt/squeezeplay/bin/sdl_smoke   # ship the aarch64 test binary, or
```

If the binary is not on the image, cross-build it on the host
(appendix A) and copy it over, then run as above.

Expected output on target:

```
SDL_Init: OK
video driver: kmsdrm
SetVideoMode: OK 640x480 bpp=16
FillRect+Flip: OK
sdl_smoke: ALL PASS
```

plus a solid dark-blue full-screen frame for ~50 ms.

PASS: `ALL PASS` and `video driver: kmsdrm`.
FAIL paths:

- `video driver: dummy` → kmsdrm backend missing (SDL2 built without
  it, or `SDL_VIDEODRIVER` overridden). Check SDL2 feature set with
  Agent 2's build (needs kmsdrm + libinput + xkbcommon).
- `SetVideoMode ... FAIL` / black screen → panel mode mismatch: dump
  `modetest -M <driver> -c` / `/sys/class/drm/card0-*/modes`, confirm
  640x480 is offered; check `SDL_KMSDRM_ORIENTATION=0`.
- GLES errors → retry with `SDL_RENDER_DRIVER=software` to isolate
  Panfrost vs modeset issues; GLES failure with software success =
  GPU/panfrost issue, not a UI bug.

## 3. Skin render check (Jive)

```sh
systemctl start squeezeplay.service
journalctl -f -u squeezeplay.service     # watch for skin errors
```

Expected: Jive home menu renders in `RG35XXHBaseSkin` at 640x480
(readable text, icons, no clipping at edges). If Jive starts in the
wrong skin, select ours via Settings → Skin, or set the default in
the skin meta (`registerSkin`, see `ui/skins/README.md`).

Checks:

- Text crisp and fully inside menu boxes (2x geometry; font
  `FreeSans.ttf` loaded from `/opt/squeezeplay/share/jive/fonts/`).
- No `imgpath`/missing-asset warnings in the Jive log (enable Jive
  log categories via `logconf.lua` — categories default to OFF, so
  silence without a logconf proves nothing).
- `jive/splash640x480.png` absent upstream → Jive falls back to
  `splash.png`; confirm no error blocks startup.

PASS: home menu usable with D-pad (see §5), no asset errors in log.
FAIL: missing images/fonts → re-check overlay manifest (§0); Lua
errors → `luac -p` the skin on host (WP1 gate) and compare bytes
with the tree (`sha256sum` vs manifest).

## 4. evtest direction confirm (physical controls)

The map (`ui/input/rg35xxh.map`) assumes mainline-DTS codes; stick
polarity is a physical fact this step confirms.

```sh
ls /dev/input/event*                      # expect gpio-keys + adc-joystick
evtest /dev/input/eventX   # gpio-keys: press every button, note codes
evtest /dev/input/eventY   # adc-joystick: move each stick full range
```

Confirm, per `ui/input/README.md`:

- A=`BTN_EAST` B=`BTN_SOUTH` X=`BTN_NORTH` Y=`BTN_WEST`
  L1/R1=`BTN_TL/TR` L2/R2=`BTN_TL2/TR2` Start=`BTN_START`
  Select=`BTN_SELECT` Menu=`BTN_MODE`, D-pad=`BTN_DPAD_*`.
- Sticks report `ABS_X/ABS_Y/ABS_RX/ABS_RY`, idle ≈ 2048, full
  deflection reaches the `press` thresholds in the map.
- **Polarity:** push stick UP → `ABS_Y` decreasing (toward 0);
  push RIGHT → `ABS_X` increasing. Same for RX/RY.

PASS: codes match the map; polarity as above.
FAIL paths:

- Wrong/missing codes → DT mismatch: fix DTS (Agent 1) or edit
  `/etc/evdev2jive/rg35xxh.map` in place and restart the daemon.
- Inverted axis → add the `flip` flag to that `axis` line in the map
  (the flag exists for exactly this) and restart the daemon.
- Noisy/jittery idle → raise `debounce_ms` / widen the
  press–release deadband in the map; re-test.

## 5. uinput end-to-end (physical press → Jive action)

```sh
systemctl status evdev2jive.service        # active (running)
evtest /dev/input/eventZ   # the 'rg35xxh-jive-keys' uinput device
```

Press each control and confirm the emitted `KEY_*` matches the map
(`rg35xxh.map` comments give the Jive action per line):

| Press | uinput key | Jive result |
|---|---|---|
| D-pad | `KEY_UP/DOWN/LEFT/RIGHT` (hold) | navigate; Left=Back, Right=Enter |
| A / hold-A | `KEY_ENTER` / +`KEY_D` | select / add_end |
| B / hold-B | `KEY_END` / +`KEY_H` | back / home |
| X / Y | `KEY_LEFTBRACE` / `KEY_F` (tap) | now-playing / favorites |
| Start / hold | `KEY_SPACE` (tap) / +`KEY_G` | play-pause toggle / stop |
| Select / hold | `KEY_HOME` / +`KEY_Q` | home / power |
| L1/R1 | `KEY_Z` / `KEY_B` (tap) | prev / next track |
| L2/R2 (+hw vol) | `KEY_MINUS` / `KEY_EQUAL` (hold) | volume, repeats while held |
| Sticks | arrows / PgUp/PgDn / Z/B | scroll / page / skip |

PASS: every row behaves as listed; no double-fires on hold-Start
(single toggle then stop); volume repeats smoothly while L2/R2 held;
no stuck keys after rapid mashing (daemon releases all on
SIGTERM — `systemctl restart` must never leave a key held).
FAIL paths:

- Key missing in Jive but present on uinput → compat/SDL translation
  issue: re-check with `SDL_VIDEODRIVER=kmsdrm` + `evtest` on the
  uinput node while Jive runs; compare against the WP1
  `Keysym20to12()` audit in `ui/README.md`.
- Doubles on long-press → daemon `long` (800 ms) vs Jive hold
  (1000 ms) race: lower the map's `long` value.
- Machine-gun toggles → a toggle key is `hold` instead of `tap` in
  the map.

## 6. Re-staging the overlay (reference)

```sh
# [host] cross-build the two target binaries (appendix A), then:
ui/install.sh --destdir /tmp/ui-overlay \
  --bins <aarch64-bin-dir> \
  --squeezeplay-src /tmp/squeezeplay@758bc11/src
# merge /tmp/ui-overlay into the rootfs (Agent 1 image assembly),
# or rsync it onto a running target for iteration.
```

## Appendix A: cross-build commands (exact)

Provenance: WP2 `wp2/ui` validation (see
`docs/test-results/wp2-ui.md`). Toolchain: Ubuntu noble
`gcc-aarch64-linux-gnu` + `libc6-dev-arm64-cross` debs extracted
rootless to `$TC` (see the evidence doc for the assembly recipe),
used with `--sysroot=$TC` and contract flags
`-march=armv8-a+crc -mtune=cortex-a53`. In the pinned container
(`build/toolchain/Dockerfile`) the same commands run with plain
`aarch64-linux-gnu-gcc` and no `--sysroot`.

```sh
CC="aarch64-linux-gnu-gcc --sysroot=$TC"   # container: drop --sysroot
CF="-march=armv8-a+crc -mtune=cortex-a53 -O2"

# input mapper (libc + kernel headers only)
$CC -std=c99 -Wall -Wextra $CF -o evdev2jive ui/input/evdev2jive.c

# splash painter (libc + zlib; arm64 zlib in sysroot)
$CC -std=c99 -Wall -Wextra $CF -o drm_splash \
  ui/splash/drm_splash.c ui/splash/pngmini.c ui/splash/blit.c -lz

# SDL smoke test (against the SDL2 fixture + compat install below)
$CC -Wall -Wextra $CF -o sdl_smoke ui/tests/sdl_smoke.c \
  -I$STAGE/sdl12-compat/include/SDL \
  -L$STAGE/sdl12-compat/lib -lSDL-1.2 \
  -L$STAGE/sdl2-fixture/lib -lSDL2

# sdl12-compat 1.2.78 (pinned tarball via ui/vendor/fetch-sdl12-compat.sh)
# needs SDL2 target headers+lib; fixture build (dummy video, build-only):
#   SDL2-2.32.10/configure --host=aarch64-linux-gnu --prefix=$STAGE/sdl2-fixture \
#     --disable-static --disable-video-x11 --disable-video-wayland \
#     --disable-video-kmsdrm --disable-video-opengl --disable-video-opengles \
#     --disable-alsa --disable-libudev --disable-joystick --disable-haptic \
#     --disable-sensor && make && make install
# then:
#   cmake -S <sdl12-compat-src> -B build-compat \
#     -DCMAKE_TOOLCHAIN_FILE=<aarch64-toolchain.cmake> \
#     -DSDL2_INCLUDE_DIR=$STAGE/sdl2-fixture/include/SDL2 \
#     -DSDL12TESTS=OFF -DSDL12DEVEL=ON -DCMAKE_BUILD_TYPE=Release
#   cmake --build build-compat   # -> libSDL-1.2.so.0 (aarch64)
```

The shipped target SDL2 (kmsdrm + libinput + xkbcommon + GLES) is
Agent 2's deliverable; `libSDL-1.2.so.0` binds to it dynamically at
runtime (`NEEDED` is libc only — it `dlopen`s SDL2), so the fixture
above affects only the compat build, never target behavior.
Verify every artifact: `file` → `ARM aarch64`.

## Appendix B: installed layout (reference)

```
<destdir>/
  opt/squeezeplay/
    bin/evdev2jive bin/drm_splash bin/init-splash.sh
    share/jive/applets/RG35XXHBaseSkin/{RG35XXHBaseSkin{Applet,Meta}.lua,images/}
    share/jive/applets/RG35XXHLandscapeSkin/{...Applet.lua,...Meta.lua,strings.txt,images/}
    share/jive/fonts/FreeSans.ttf FreeSansBold.ttf   (from squeezeplay dejavu 2.37)
    share/squeezebox-ui-manifest.txt
  etc/evdev2jive/rg35xxh.map
  usr/share/squeezebox/splash_640x480.png
```

Bins 0755, data 0644. The manifest holds a sha256 per file and is
checked by §0.
