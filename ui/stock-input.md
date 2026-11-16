# Stock input: by-name evdev discovery (vendor 4.9 kernel track)

Scope: input on the **stock** card (vendor 4.9.170). Verified device names
([hardware inventory](../docs/hardware.md#verified-input-discover-by-name-never-hardcode-eventn)):

- `axp2202-pek` — power button (PMIC power-key),
- `ANBERNIC-keys` — GPIO keys, joystick, analog,
- `dierct-keys-polled` — (sic, vendor typo) polled direct keys.

Numbers observed at inventory time (event0/1/2) **can shift** — never
hardcode `eventN`. This doc is the B2 stock track: guidance + probe
commands only, no change to shipped code.

## 1. By-name discovery (the rule)

Match devices by their `EVIOCGNAME` name, exactly as `evdev2jive` already
does: it scans `/dev/input/event*`, reads each name via `EVIOCGNAME`, and
keeps devices whose name contains a `device <substring>` pattern from the
map (`ui/input/evdev2jive.c`, `dev_matches`/`open_inputs`). The shipped
map matches mainline names:

```
device gpio-keys
device adc-joystick
```

A stock-track map keeps the same mechanism but matches **stock** names:

```
device ANBERNIC-keys
device dierct-keys-polled
```

Substring match is case-sensitive — copy names exactly
(`dierct-keys-polled` with the vendor typo).

`/dev/input/by-id/*` and `/dev/input/by-path/*` symlinks are the shell
equivalent for humans and probe scripts: resolve the name → `eventN`
mapping through them instead of guessing numbers.

## 2. Expected handling per device

### `ANBERNIC-keys` (the main gamepad input)

This is the stock equivalent of mainline `gpio-keys` + `adc-joystick` in
one node: buttons, D-pad, sticks. Expected handling:

- Primary `device` line in the stock map; all gamepad `key`/`axis` lines
  attach to the codes **actually emitted** by this node.
- Codes are NOT assumed from mainline DTS. The mainline map assumes
  `BTN_EAST/SOUTH/NORTH/WEST`, `BTN_TL/TR/TL2/TR2`, `BTN_START/SELECT/
  MODE`, `BTN_DPAD_*`, `ABS_X/Y/RX/RY` 0..4096 (`ui/input/README.md`,
  `ui/input/rg35xxh.map`). The vendor 4.9 driver may emit different codes
  (e.g. `KEY_*` instead of `BTN_*`, different ABS ranges). The `evtest`
  pass in §4 exists to read the real codes before writing the stock map.
- Stick polarity/range (`flip`, `center/press/release`) likewise comes
  from the probe, not from the mainline map.

### `dierct-keys-polled` (secondary polled keys)

Vendor polled-GPIO device. Expected handling:

- Include as a second `device` line so its keys flow through the same
  mapper — but only after the probe shows what it emits (it may be
  volume keys, function keys, or duplicates of `ANBERNIC-keys`).
- If it emits duplicates of the main node, prefer ONE source per physical
  control (drop the noisier/duplicated line from the stock map) to avoid
  double-fires.

### `axp2202-pek` (power button) — hands off by default

- Do NOT match it in the stock map initially. Rationale: the PMIC
  power-key drives hardware power behavior (long-press cuts power at the
  PMIC level regardless of software); grabbing it in the mapper risks
  fighting init/systemd power-key handling, and a stuck grab could wedge
  power-off paths.
- Default: let the stock init system own `KEY_POWER` from this node.
- Optional later step (explicit user approval, reversible): add
  `device axp2202-pek` + `key KEY_POWER KEY_Q tap` (Jive power action)
  only after confirming via `evtest` that it emits plain `KEY_POWER`
  make/break and that nothing else on stock consumes it.

## 3. What stays the same from the mainline input path

- The `evdev2jive` binary itself is kernel-agnostic (C99, libc + kernel
  headers only; `ui/BRINGUP.md` appendix A cross-build). Only the `.map`
  `device` lines + code tables differ on stock.
- Tap/hold/long semantics, `grab`, `EV_REP` tuning, and the uinput node
  (`rg35xxh-jive-keys`) behave identically — but verify `/dev/uinput`
  (or `/dev/input/uinput`) exists on the 4.9 kernel (probe §4.5).
- SDL1.2-fbcon reads the Linux console keyboard, NOT evdev directly, so
  the uinput→console-keyboard path must be confirmed on stock (open
  question 3 in `ui/stock-fbcon-BUILD.md` §6 has a graphics analogue;
  input analogue: does the vendor console consume uinput keys?).

## 4. Probe commands (user-run, read-only except evtest observation)

Run on the device over the UART root shell. Nothing here writes state
(`evtest` only prints events while the user presses controls).

```sh
# 4a. Inventory: kernel view + stable symlinks (never trust eventN alone)
cat /proc/bus/input/devices
ls -l /dev/input/
ls -l /dev/input/by-id/ /dev/input/by-path/ 2>&1
# 4b. Per-node identity (udev view; confirms name<->node binding)
for ev in /dev/input/event*; do
  echo "== $ev"; udevadm info --query=all --name="$ev" 2>/dev/null \
    | grep -E 'ID_INPUT|DEVNAME|ID_PATH' || echo "(no udev data)"
done
# 4c. evtest presence + capability dump per node (no presses needed)
command -v evtest || echo "NO evtest on stock"
evtest --list 2>/dev/null || ls /dev/input/event*
# For each N from the by-path listing (example N=1):
#   evtest /dev/input/event1   # prints supported EV/KEY/ABS first, then live events
# 4d. Live code capture (the actual map source of truth):
#   Run evtest on the ANBERNIC-keys node, press EVERY control once
#   (D-pad, A/B/X/Y, Start/Select/Menu, L1/R1/L2/R2, stick clicks,
#   sticks full-range + diagonals), and record:
#     - key events: code name + value 1/0 (e.g. BTN_SOUTH? KEY_X?)
#     - ABS events: code + min/max/idle + direction polarity
#   Repeat on the dierct-keys-polled node (press its keys).
#   Repeat on axp2202-pek ONLY with a short power tap (do NOT long-press).
# 4e. uinput availability (mapper output path)
ls -l /dev/uinput /dev/input/uinput 2>&1
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_UINPUT|CONFIG_INPUT_EVDEV' \
  || grep -E 'UINPUT|EVDEV' /boot/config-* 2>/dev/null || echo "(no kernel config visible)"
lsmod | grep -i -E 'uinput|evdev' || echo "(uinput/evdev built-in or absent — see /dev nodes)"
```

Recording template (paste into the evidence doc / probe output bundle):

```
node: /dev/input/eventN  by-path: <symlink>  name: ANBERNIC-keys
  KEY/BTN codes seen: ...
  ABS_X: min..max idle=...  up=decreases? ...
  ABS_Y: ...
  ABS_RX: ...  ABS_RY: ...
node: ... name: dierct-keys-polled
  codes seen: ...
node: ... name: axp2202-pek
  codes seen: ... (short tap only)
uinput: /dev/uinput present|absent   evtest: present|absent
```

The stock `.map` is written from this template — no map without it.
