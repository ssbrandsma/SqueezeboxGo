# Input — evdev → Jive keyboard map (RG35XX H)

`evdev2jive` (C99, no deps beyond libc + kernel headers) reads the gpio-keys
and adc-joystick event devices and emits a clean keyboard stream on a uinput
device (`rg35xxh-jive-keys`) that SDL2 picks up like any USB keyboard.

## Why this reaches Jive with zero framework patches

Traced end to end in the pinned sources (WP1):

- SDL2 `evdev`/`libinput` turns `KEY_*` into `SDLK_*`; sdl12-compat
  `Keysym20to12()` forwards arrows, Return, Home/End, Menu, PageUp/Down,
  Print, F1–F15, Power and low-ASCII 1:1, and **drops SDL2-style repeats**
  while **synthesizing SDL1.2 repeats** from Jive's
  `SDL_EnableKeyRepeat(500, 100)`.
- Jive (`jive_framework.c`) maps those keysyms to `JIVE_KEY_*`: arrows fire
  `KEY_PRESS` on every down (repeatable), other mapped keys get
  down/press/up plus a 1000 ms hold timer. Anything else with `unicode != 0`
  (Jive calls `SDL_EnableUNICODE(1)`, compat fills it from text input)
  becomes `CHAR_PRESS`, which Lua `charActionMappings`
  (`share/jive/InputToActionMap.lua`) turns into actions: play/pause/stop,
  volume, jump (prev/next track), now-playing, favorites, power, …

So the daemon emits plain keyboard keys; transport control needs no patched
SDL and no `jive_framework.c` change. Verified facts that shaped the map:

- `pause` action = `_player:togglePause()` → Start emits `space` (play/pause
  toggle); hold-Start emits `g` (stop). The intermediate toggle on a
  hold-Start is expected: end state is deterministically stopped.
- `jump_rew/fwd` = prev/next track → L1/R1 emit `z`/`b`.
- `+`/`=`/`-` = volume → L2/R2 and the dedicated hw vol keys emit
  `-`/`=` as **hold** keys so holding repeats volume via the chain.
- `[`/`f` = now-playing/favorites → X/Y emit `[`/`f` as one-shot taps.
- D-pad/sticks emit arrows (hold); `LEFT`→back / `RIGHT`→go come free from
  `keyActionMappings` (contract's Left=Back / Right=Enter).
- A/B/Select emit Enter/End/Home (hold) with daemon long-press at 800 ms —
  deliberately shorter than Jive's 1000 ms hold so the daemon's alternate
  (`d`=add_end, `h`=go_home, `q`=power) wins cleanly, no doubles.
- Right stick Y = PageUp/Down (repeatable page scroll), X = `z`/`b` skip.
- ThumbL/R = `c` (pause) / `g` (stop); Menu = Menu key (ADD).

Input codes are mainline-DTS ground truth (`sun50i-h700-anbernic-rg35xx-*`):
A=`BTN_EAST`, B=`BTN_SOUTH`, X=`BTN_NORTH`, Y=`BTN_WEST`,
L1/R1=`BTN_TL/TR`, L2/R2=`BTN_TL2/TR2`, Start=`BTN_START`,
Select=`BTN_SELECT`, Menu=`BTN_MODE`, sticks=`ABS_{X,Y,RX,RY}` 0..4096
(the driver's inverted ranges are self-compensating; physical stick
direction is a WP2 `evtest` check item, `flip` exists if needed).

## Behavior contract (implemented + tested)

- `tap`: one short tap per physical press (auto-release at `tap_ms`);
  toggle actions can never machine-gun, whatever the chain repeats.
- `hold`: press on down, release on up (+`debounce_ms` collapse window);
  repeat comes from kernel softrepeat (`EV_REP`, `rep_*_ms`, for direct
  evdev consumers) and compat synthesis (for Jive).
- `long MS KEY`: clean switch at MS — release primary, tap alternate once;
  the later physical release is a no-op. Kernel `value=2` repeats and
  unmapped codes are dropped. `SIGTERM`/`SIGINT` releases all held keys.
- Axis hysteresis: press past `press`, release inside `release`, clean
  flip when crossing center. Stick position at startup is seeded via
  `EVIOCGABS` so a held stick never starts stuck.

## Files

- `evdev2jive.c` — daemon (`MAP` live, `--test MAP SCRIPT`, `--dump-map`).
- `rg35xxh.map` — default map (this is the configurable mapping file).
- `tests/` — `run_tests.sh` + 10 recorded scripts with hand-computed
  expected outputs + 3 config-lint negatives.

## Install / service (for Agent 1)

- Install binary to `/opt/squeezeplay/bin/evdev2jive`, map to
  `/etc/evdev2jive/rg35xxh.map` (edit in place to retune; `HUP` not
  needed — daemon is tiny, restart it).
- Needs read on `/dev/input/event*` (group `input`) + `/dev/uinput`
  (udev rule / `uinput` group). Runs as a `Type=simple` unit ordered
  `Before=squeezeplay.service`; squeezeplay needs no input env vars.
- Suggested unit (platform owns the file, snippet only):

```ini
[Unit]
Description=RG35XX H gamepad to Jive keyboard map
Before=squeezeplay.service
[Service]
Type=simple
ExecStart=/opt/squeezeplay/bin/evdev2jive /etc/evdev2jive/rg35xxh.map
Restart=on-failure
[Install]
WantedBy=multi-user.target
```

## Host validation

`tests/run_tests.sh`: native build with `-Wall -Wextra` (zero warnings)
+ 10 deterministic `--test` replays diffed against hand-computed outputs
+ 3 bad-map rejections. Live uinput/evdev paths need hardware or root +
`uinput` and are WP2 items (same binary, same map).
