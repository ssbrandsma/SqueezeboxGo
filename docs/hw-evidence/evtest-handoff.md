# evtest capture plan — FOR THE OWNER (human fingers required)

Status: PREPARED, not run (agent must not grab input devices unattended).
Goal: verify every button/stick against the DT-decoded map so UI can
finalize `evdev2jive.map`. Reference: `docs/hw-evidence/stock-dt-notes.md`
§Input (19 DT codes).

## Safety

- `evtest` GRABS the device exclusively while running: dmenu will not see
  buttons meanwhile. Harmless (grab releases on Ctrl-C), but run ONE evtest
  at a time and Ctrl-C when done with each device.
- **event0 (`axp2202-pek`) is the POWER button — hands off.** Capture it
  with `--query` state only if curious; NEVER hold/power-press for the test.
- Run as `muse` over SSH (already in group `input` — no sudo needed).
  A second SSH session is handy: one runs evtest, the other watches.

## Commands (exact, in order)

```sh
# 0. sanity: nodes + names (no fingers, no grab)
ls -l /dev/input/by-path/
cat /proc/bus/input/devices | grep -E "^N|^H"

# 1. ANBERNIC-keys (main pad: ABXY, shoulders, stick, Start/Select)
evtest /dev/input/by-path/platform-soc@03000000:gpio_keys-event-joystick
```

With #1 running, press ONE at a time, ~1 s apart, and note each
`code NNN (NAME), value 1` line:

| Press | Expect code | Name |
|---|---|---|
| A / B / X / Y | 304 / 305 / 306 / 307 | BTN_SOUTH / EAST / NORTH / WEST |
| L1 / R1 | 308 / 309 | BTN_TL / BTN_TR |
| Select / Start | 310 / 311 | BTN_SELECT / BTN_START |
| L3 (stick click) | 313 | BTN_THUMBL |
| L2 / R2 | 314 / 315 | BTN_TL2 / BTN_TR2 |
| R3 | 316 | BTN_THUMBR |
| Menu | 312 | BTN_MODE |
| Left analog stick (move full circle) | ABS_X / ABS_Y values sweep | |
| Dpad Up/Down/Left/Right | ABS_HAT0Y (17) / ABS_HAT0X (16) | hat, NOT keys |

Ctrl-C, then:

```sh
# 2. dierct-keys-polled (vendor typo is real; second key matrix)
evtest /dev/input/by-path/platform-dierct-keys-polled-event
```

Press each remaining button (volume +/-, function keys, any extra keys on
the shell) one at a time; record every `code NNN (NAME)` seen plus which
physical control produced it. Expected set is unknown — THIS is the
discovery run (DT NOTE: compare against `stock-dt-notes.md` §Input).

```sh
# 3. power key — QUERY ONLY, do not press anything
evtest --query /dev/input/by-path/platform-twi5-platform-axp2101-pek.0-event EV_KEY BTN_TL2
echo "query exit=$? (0/10 = state, anything else = note it)"
```

## What to send back

For device #1: one line per control — `<control> -> code <NNN> (<NAME>)`,
flagging ANY code that differs from the Expect column. For device #2: the
full control→code list. Plus the query exit code from #3. Copy the raw
evtest output into the reply if unsure — the agent will decode it.
