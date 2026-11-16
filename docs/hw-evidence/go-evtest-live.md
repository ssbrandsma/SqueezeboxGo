# go-evtest LIVE capture — PREPARED, not run (no fingers; agent never waits for input)
# Agent: HW go-redeploy, 2026-11-16. Device nodes verified this session (see §0).
# Supersedes nothing: partner doc docs/hw-evidence/evtest-handoff.md still holds
# (code table + safety); this file is the exact live-session script with
# verified-first-lines so the owner/lead can run it verbatim.

## §0. Agent-verified preconditions (no input waited, `timeout 5` throughout)

```text
$ command -v evtest && timeout 5 evtest --query \
    /dev/input/by-path/platform-soc@03000000:gpio_keys-event-joystick EV_KEY BTN_SOUTH; echo "q1_rc=$?"
/usr/bin/evtest
q1_rc=0
$ timeout 5 evtest --query \
    /dev/input/by-path/platform-dierct-keys-polled-event EV_KEY BTN_SOUTH; echo "q2_rc=$?"
q2_rc=0
```

- evtest present, both by-path nodes resolve, `--query` (stateless, NO grab,
  returns instantly) works. rc=0 means "key currently UP".
- Full node list (verified same session):
  `/dev/input/event0` axp2202-pek (power — HANDS OFF except query),
  `/dev/input/event1` ANBERNIC-keys (+ js0), `/dev/input/event2`
  dierct-keys-polled (vendor typo is real). by-path names as in the
  commands above + `platform-twi5-platform-axp2101-pek.0-event` for event0.
- The agent NEVER runs bare `evtest <node>` (it blocks waiting for fingers);
  every agent-side check uses `timeout 5` + `--query` only.

## §1. Owner live-capture script (verbatim; second SSH session recommended)

```sh
# 0. sanity (no fingers, no grab) — expect 4 by-path names + 3 N:/H: pairs
ls -l /dev/input/by-path/
cat /proc/bus/input/devices | grep -E "^N|^H"
```

Expected first lines:

```text
platform-dierct-keys-polled-event
platform-soc@03000000:gpio_keys-event-joystick
platform-soc@03000000:gpio_keys-joystick
platform-twi5-platform-axp2101-pek.0-event
N: Name="axp2202-pek"
H: Handlers=kbd event0
N: Name="ANBERNIC-keys"
H: Handlers=kbd js0 event1
N: Name="dierct-keys-polled"
H: Handlers=kbd event2
```

```sh
# 1. ANBERNIC-keys — press ONE control at a time (~1 s apart), note each
#    `code NNN (NAME), value 1` line, then Ctrl-C.
evtest /dev/input/by-path/platform-soc@03000000:gpio_keys-event-joystick
```

Expected first lines (before any press):

```text
Input driver version is 1.0.1
Input device ID: bus 0x19 vendor 0x1 product 0x1 version 0x100
Input device name: "ANBERNIC-keys"
Supported events:
  Event type 0 (EV_SYN)
  ...
Testing ... (interrupt to exit)
```

Per-control expectations (flag ANY deviation — code, name, or missing):

| Press | Expect code | Name |
|---|---|---|
| A / B / X / Y | 304 / 305 / 306 / 307 | BTN_SOUTH / EAST / NORTH / WEST |
| L1 / R1 | 308 / 309 | BTN_TL / BTN_TR |
| Select / Start | 310 / 311 | BTN_SELECT / BTN_START |
| L3 (stick click) | 313 | BTN_THUMBL |
| L2 / R2 | 314 / 315 | BTN_TL2 / BTN_TR2 |
| R3 | 316 | BTN_THUMBR |
| Menu | 312 | BTN_MODE |
| Left stick full circle | ABS_X / ABS_Y sweep | — |
| Dpad Up/Down/Left/Right | ABS_HAT0Y (17) / ABS_HAT0X (16) | hat, NOT keys |

```sh
# 2. dierct-keys-polled — DISCOVERY run: press every remaining control
#    (volume +/-, function keys, extras), one at a time; record each
#    `code NNN (NAME)` + which control produced it. Then Ctrl-C.
evtest /dev/input/by-path/platform-dierct-keys-polled-event
```

```sh
# 3. power key — QUERY ONLY, press nothing
evtest --query /dev/input/by-path/platform-twi5-platform-axp2101-pek.0-event EV_KEY BTN_TL2
echo "query exit=$? (0/10 = state, anything else = note it)"
```

## §2. Why this capture matters now (mapper-gap diagnosis)

Headless probing this session PROVED jive (SDL1.2-fbcon, VT-path
keyboard) is deaf to unmapped gamepad codes: BTN_* (304+) carry no
VT keysym, so the pad cannot reach jive without the evdev2jive
mapper (absent from the 0.1.0 package — known limitation). The event2
capture may reveal VT-mapped codes (arrows/enter/F-keys?) that WOULD
pass through — record every code exactly; the mapper design (UI agent)
depends on the full set. If a USB keyboard is handy, also confirm it
navigates jive in a menu run (healthy-SDL-path control experiment).

## §3. What to send back

One line per control: `<control> -> code <NNN> (<NAME>)` (+ hat/ABS
sweeps noted), the §3 query exit code, and the raw evtest output
pasted if unsure. Plus: USB-keyboard-in-jive result if tried.
