# Stock bundle — reversible Jive deployment on the stock OS (track B3)

Runs Jive on the **stock Ubuntu 22.04 system** without modifying it:
copy one directory, `systemctl stop` the gaming frontend, launch Jive,
`systemctl start` the frontend back. Reboot alone restores stock
behavior even if you do nothing (nothing is disabled, masked, or
reconfigured).

Service shape follows `standalone/` conventions (small pid-less
start/stop wrappers, env from a sourced file, state under `state/`),
but this bundle is **deliberately NOT a systemd unit**: installing a
unit would be a system write, which this track forbids.

## Layout

```text
bundle/                  # this dir; install.sh copies it verbatim
├── install.sh           # copy bundle to /opt/squeezebox-stock or $HOME/… (no system writes)
├── run-jive.sh          # stop frontend (stop only) + exec jive with jive-env.sh
├── restore.sh           # restart frontend and/or delete the bundle
├── lib-safety.sh        # shared plan/confirm/refusal helpers (sourced, not run)
├── jive-env.sh          # SDL/ALSA/Jive knobs (edit the INSTALLED copy)
├── frontend-unit.txt.example  # template: which unit run-jive.sh may stop
└── state/               # created at runtime (not in git)
    ├── stopped-unit     # unit run-jive.sh stopped (restore.sh reads this)
    └── jive-home/       # JIVE_HOME_DIR: keeps Jive writes inside the bundle
```

Optional payload (not in git, you provide it):

```text
<install-dest>/jive/jive   # Jive binary run-jive.sh will find automatically
```

## Flow (exact commands, on device as root)

```sh
# 0. Frontend unit FIRST — from your probe tarball (never guess).
#    See "Identifying the frontend unit" below, then either:
cp frontend-unit.txt.example frontend-unit.txt
$EDITOR frontend-unit.txt            # one bare unit name, e.g. emulationstation.service
#    ... or pass --frontend-unit every time (overrides the file).

# 1. Install (copies bundle only; --dry-run first to see the plan).
bash install.sh --dry-run
bash install.sh --dest /opt/squeezebox-stock   # or $HOME/squeezebox-stock
cd /opt/squeezebox-stock

# 2. Rehearse the run (checks binary + unit, stops/starts NOTHING).
bash run-jive.sh --frontend-unit "$(cat frontend-unit.txt)" --dry-run

# 3. Run (stops frontend via systemctl stop ONLY, then execs jive).
bash run-jive.sh --frontend-unit "$(cat frontend-unit.txt)"

# 4. Back to stock gaming UI (from a second shell, or after jive exits).
bash restore.sh --restart-frontend

# 5. Full removal (after step 4, or just reboot instead).
bash restore.sh --remove
```

Every script prints its `[plan]` before acting and asks for a typed
`YES` unless `--yes` is given. Every script exits nonzero with a
`[refuse]` line instead of doing anything questionable.

## Identifying the frontend unit (required, once per stock image)

1. Unpack the probe tarball on your host (`tar -xzf stock-probe-*.tar.gz`).
2. `90-frontend-hunt.txt` → the frontend process and its PID owner.
3. `50-processes-services.txt` → the `*.service` in `running` state that
   owns that process. Cross-check `systemctl status <name>` on device:
   Main PID must be the frontend process.
4. `systemctl cat <name>` must show a frontend ExecStart. If it shows
   getty, sshd, NetworkManager, or anything under `/lib/systemd/`,
   you have the WRONG unit — go back to step 2.
5. Write the bare name into `frontend-unit.txt` (installed copy).

`run-jive.sh` additionally refuses to stop infrastructure units
(systemd-*, dbus, ssh/sshd, NetworkManager/networkd, logind, udev,
getty/serial-getty, and the `*.target` graph roots) and refuses unit
names with shell metacharacters.

## Environment (jive-env.sh)

| Knob | Default | Source |
|---|---|---|
| `JIVE_BIN` | bundle `jive/jive`, then `/opt/squeezeplay/bin/jive` | install layout |
| `SDL_VIDEODRIVER` | `fbcon` | stock has `/dev/fb0`, no `/dev/dri` (verified) |
| `SDL_FBDEV` | `/dev/fb0` | verified |
| `SDL_AUDIODRIVER` | `alsa` | verified ALSA cards |
| `ALSA_DEVICE` / `USEALSA_DEVICE` | `hw:CARD=audiocodec,DEV=0` | verified card 0 |
| `SQUEEZEPLAY_NOPLAYBACK` | `0` (`1` = UI-only, no ALSA open) | contracts |
| `JIVE_HOME_DIR` | `$BUNDLE_ROOT/state/jive-home` | keep writes in bundle |

Confirm `SDL_VIDEODRIVER` against `20-sdl.txt` (which SDL the stock
image ships) and the ALSA device against `30-alsa.txt` before the
first real run. For a display-only smoke test, set
`SQUEEZEPLAY_NOPLAYBACK=1` so Jive never opens the (possibly occupied)
PCM.

## Reversibility proof

| Action | Touched | Untouched |
|---|---|---|
| probe | new tarball in cwd | everything (read-only) |
| install | new dir (`/opt/squeezebox-stock` or `$HOME/…`) | `/etc`, `/usr`, units, bootloader, kernel |
| run-jive | runtime `systemctl stop <unit>` + `state/` files | unit files, enables, masks (reboot restores stock) |
| restore --restart-frontend | `systemctl start <same unit>` | everything else |
| restore --remove | deletes the bundle dir only (allowlist-checked) | everything else |

If anything goes wrong mid-run: a plain `reboot` returns the device to
the stock gaming UI, because no persistent state was ever changed.
