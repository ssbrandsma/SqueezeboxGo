# SqueezeboxGo — StockOS App Center package (RG35XX H)

Native Squeezebox (Jive) as a StockOS App Center app: no reflash, no
bootloader/kernel changes, games and saves untouched. Install = copy one
ZIP's `APPS/` content to the card's `Roms/`; launch from App Center;
return via Jive's **Return to Anbernic** home item — no reboot.

Owner: GO-APP (host-only). Device install + lifecycle validation: GO-HW.

## Layout

```text
squeezebox-go/
  README.md            this file (contracts)
  INSTALL.md           user install guide (download ZIP, extract, launch)
  UNINSTALL.md         removal guide (idempotent + reversible)
  VERSION              package version (pack.sh stamps it into the ZIP)
  pack.sh              reproducible ZIP builder (host)
  apps/SqueezeboxGo.sh App Center entry (FAT-safe POSIX sh, runs as root)
  runtime/launch.sh    ext4 launcher (claim, snapshot, run, always restore)
  runtime/restore.sh   mixer + framebuffer restore helper
  icon/make-icon.py    stdlib-only 160x120 RGBA icon generator (git stays
                       text-only; the PNG is generated at pack time)
  tests/test-package.sh   package-content test suite (committed)
  tests/test-jive-action.lua  host harness executing the Jive action
```

The Jive side of this feature (owned by the same agent) lives in the
shared tree, fork-free:

```text
squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH/
  SqueezeboxRG35XXHMeta.lua    registers the home item iff SQUEEZEBOX_GO=1
  SqueezeboxRG35XXHApplet.lua  returnToFrontend() + exit code 42
  strings.txt                  GO_RETURN_TO_ANBERNIC token
```

## App Center mechanism (verified from references; device is truth)

- `Roms/APPS/<Name>.sh` + `Roms/APPS/Imgs/<Name>.png` (**240x180 RGBA**, device-verified)
  + optional `Roms/APPS/<Name>/` payload dir.
- TF slot 01/02 selectable; scripts run as **root**; **stdout is lost**
  (log to files).
- `Roms` is **VFAT** (no symlinks, no permission bits) → the ext4 runtime
  lives at `$SQUEEZEBOX_GO_ROOT` (`/opt/squeezebox-go`, else
  `$HOME/squeezebox-go`); the APPS script only installs/verifies then
  execs the runtime launcher. Mount paths are confirmed on device (GO-HW).

## ZIP layout (pack.sh output)

```text
SqueezeboxGo-<ver>-stockos-rg35xxh.zip
  APPS/SqueezeboxGo.sh              entry (install/upgrade + exec)
  APPS/Imgs/SqueezeboxGo.png        icon (generated, 240x180 RGBA)
  APPS/SqueezeboxGo/VERSION         payload version (upgrade detection)
  APPS/SqueezeboxGo/SHA256SUMS      payload hash (entry verifies pre-install)
  APPS/SqueezeboxGo/payload.tar.gz  ext4 runtime:
    jive/            Jammy squeezeplay tree (aarch64, glibc <= 2.34)
                     + SqueezeboxRG35XXH applet overlay (this repo)
                     + RG35XXHBaseSkin overlay (ui/, read-only packaging use)
    lib-fbcon/       stock-kernel framebuffer libSDL (shadows dummy video)
    launch.sh, restore.sh, VERSION, MANIFEST, config/
```

`jive` carries `RUNPATH /opt/squeezeplay/lib`, so launch.sh prepends the
real lib dirs via `LD_LIBRARY_PATH` (lib-fbcon first, then jive/lib);
Lua search paths bootstrap relative to the executable and relocate fine.

## Exit-code contract

| Jive exit | Meaning | Launcher behavior |
|---|---|---|
| `42` (`EXIT_RETURN_TO_FRONTEND`) | user chose Return to Anbernic | clean path: restore mixer/fb, restart frontend, exit 0 |
| anything else (0, 1, 143, …) | quit / crash / killed | SAME restore + restart, logged as UNEXPECTED, exit 0/1 on restore outcome |

Rules:

- The Jive action ALWAYS ends in `os.exit(42)` — every cleanup step is
  best-effort (`pcall` + log), never a fall back into the event loop.
  (`Framework:quit()` cannot carry a code: it always yields exit 0 via
  JiveMain, so `os.exit` is the carrier; process teardown releases fds.)
- launch.sh restores + restarts the frontend on EVERY exit path via its
  `EXIT`/`TERM`/`INT` trap — a crash never leaves the device UI-less.
- launch.sh's own exit status reports the RESTORE outcome (0 restored,
  1 restore failed), never Jive's code.

## Environment contract (launch.sh → Jive)

| Variable | Value | Purpose |
|---|---|---|
| `SQUEEZEBOX_GO` | `1` | gates the home item (shared tree, no fork) |
| `SQUEEZEBOX_GO_ROOT` | ext4 runtime root | fallback restore-helper path |
| `SQUEEZEBOX_GO_STATE` | RAM state dir | mixer/fb snapshots, logs |
| `SQUEEZEBOX_GO_RESTORE` | `$ROOT/restore.sh` | helper the Jive action execs |
| `SQUEEZEBOX_GO_EXIT_FRONTEND` | `42` | must match the Lua constant |
| `NP_STATE_DIR` | `$STATE/np` | Now Playing `nowplaying.json` (RAM-backed, per `standalone/base/nowplaying-schema.md`) |
| `JIVE_HOME_DIR` | `$ROOT/config/jive-home` | persistent Jive settings |
| `LD_LIBRARY_PATH` | lib-fbcon : jive/lib | fbcon SDL shadow + relocated RUNPATH |
| `SDL_VIDEODRIVER` / `SDL_FBDEV` | `fbcon` / `/dev/fb0` | stock has fb0, no DRI (verified) |
| `SDL_AUDIODRIVER` / `USEALSA_DEVICE` | `alsa` / `hw:CARD=audiocodec,DEV=0` | verified card 0 |

Operator overrides: `SQUEEZEBOX_GO_FRONTEND` (unit name),
`SQUEEZEBOX_GO_NO_FRONTEND_STOP=1` (leave frontend running),
`SQUEEZEBOX_GO_NO_ESCAPE=1` (skip cgroup escape),
`SQUEEZEBOX_GO_JIVE_ARGS` (extra jive args), plus persistent
`$ROOT/config/env.sh` (sourced when present) and
`$ROOT/config/frontend-unit.txt`.

## Frontend claim strategy (GO-HW validates on device)

1. Default: `systemctl stop launcher.service` (stop ONLY — never
   disable/mask; reboot alone restores stock), pre-state recorded in
   `$STATE/frontend.stamp`, restarted after Jive exits iff it was active.
2. Before stopping, launch.sh re-execs itself under
   `systemd-run --scope` (after a no-op probe) so the stop cannot
   SIGTERM us via our own cgroup; without escape it continues in place
   (safe failure: the trap restores the frontend and the user is back
   in App Center).
3. Infrastructure units are refused (same policy as
   `stock/bundle/lib-safety.sh`); frontend handling is skipped cleanly
   with a warning when systemctl is absent.

Open device questions for GO-HW: exact frontend unit name per stock
image, whether App Center already suspends dmenu (→
`SQUEEZEBOX_GO_NO_FRONTEND_STOP=1` may become the default), and the
cgroup the APPS script lands in.

## State map

| Path | Backing | Content |
|---|---|---|
| `$ROOT/` (`/opt` or `$HOME`) | ext4 (persistent) | runtime, `config/` (settings, env overrides), `install.log` |
| `/dev/shm/squeezebox-go/` (else `/tmp/…`) | RAM (fresh each boot) | `logs/` (launch/jive/restore), `tmp/`, `np/`, snapshots, frontend stamp |

## Known limitations (host-side view; GO-HW confirms)

- Input: handheld buttons reach Jive only through SDL keyboard events;
  the evdev2jive mapper is NOT in this package (GO-HW/UI follow-up).
  Button navigation is human-gated on device.
- Sleep: stock auto-suspends after ~80 s idle (dmenu timer); stopping
  the frontend likely stops it (to verify on device).
- Skin: `RG35XXHBaseSkin` ships in the payload; first-run skin
  selection falls back gracefully if a skin id is ever missing
  (SelectSkin → reload picks a registered skin; never a crash).

## Never

No reflash, no bootloader/kernel/partition/PMIC changes, no dmenu.bin
patches, no game/save deletes, no `apt upgrade/autoremove`, no permanent
frontend disable. Every write is confined to `Roms/APPS/SqueezeboxGo*`
(VFAT) + one ext4 runtime dir + RAM state.
