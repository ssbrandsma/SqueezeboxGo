# rg35xxh_bsp — RG35XX H platform HAL applet (WP2 skeleton)

Resident device applet + Lua C module for the Anbernic RG35XX H (Allwinner
H700, 640x480). Follows the Fab4 pattern from
`squeezeos-squeezeplay@766b6a8:src/squeezeplay_fab4` (applet subclass +
`<machine>_bsp` C module installing a `jive_sdlevent_pump` hook), with
RG35XX-H specificity only — no touch/IR/ambient hardware assumptions.

## Layout (source)

```
rg35xxh_bsp/
  README.md                        this file
  src/rg35xxh_bsp.c                Lua C module (uevent pump)
  share/applets/SqueezeboxRG35XXH/
    SqueezeboxRG35XXHApplet.lua    device applet (brightness/power/audio)
    SqueezeboxRG35XXHMeta.lua      defaults + service registration
    loadPriority.lua               loadPriority=1 (resident, fab4-style)
    strings.txt                    EN strings (GOODBYE/BATTERY_*/BSP_*)
```

Install mapping (see `../INSTALL-LAYOUT.md`):

| Source | Target |
|---|---|
| `src/rg35xxh_bsp.so` (built) | `/opt/squeezeplay/lib/lua/5.1/rg35xxh_bsp.so` |
| `share/applets/SqueezeboxRG35XXH/` | `/opt/squeezeplay/share/jive/applets/SqueezeboxRG35XXH/` |

## Contract HAL coverage (`docs/interface-contracts.md`, Platform HAL)

| HAL slot | Skeleton state |
|---|---|
| Display 640x480 | via Agent 4 skin + SDL/KMS; applet sets default skin |
| backlight/brightness | `getBrightness/setBrightness` via probed `/sys/class/backlight/*` |
| keys/power events | keys via SDL (Agent 4 evdev2jive map, not grabbed here); power key as jive key event; uevents via C pump |
| battery %/charging | `batteryPercent/chargingState` via probed `/sys/class/power_supply/*`, nil when absent |
| standby/wake/shutdown | `standby` = screen-blank (suspend-to-RAM NOT validated); `poweroff/reboot` via `/sbin` |
| audio enumerate/select | `audioDevices` from `/proc/asound/cards`; `selectAudioDevice` records alias; live re-open TODO |
| network up/down, config store | not in skeleton (jive Networking + userpath cover it) |

## Deliberate deviations from fab4

1. Subclasses `applets.Linux.LinuxApplet`, not `SqueezeboxApplet`: the
   latter lives in the squeezeos tree and is absent from the pinned
   `squeezeplay@758bc11` open tree.
2. The C pump serves the uevent socket only. Fab4 grabbed evdev nodes
   directly because SDL 1.2 had no driver for its clearpad/IR; on RG35XX H
   every button already arrives as SDL events through the evdev2jive map.
3. `parseCpuInfo` is overridden: upstream `LinuxApplet.parseCpuInfo` has a
   `string.gsub/serial` typo that performs arithmetic on a function and
   raises on any ARM cpuinfo with a Serial line. Ours never raises.
4. `poweroff/reboot` call `/sbin/poweroff|reboot` (+ player disconnect)
   instead of the absent `squeezeos.*` functions LinuxApplet uses.
5. `alsaEffectsDevice` is unset (no effects fork): single-holder audio
   with no dmix (Agent 3 design) means a second `jive_alsa` on the same
   PCM would fail. Needs a Lead/Agent 3 effects-routing decision.

## Status / TODO (needs hardware)

- [x] C module syntax-checked for aarch64 against real jive headers
- [x] Lua files byte-compile (PUC Lua 5.1.5 `luac -p`)
- [ ] Wire `rg35xxh_bsp.so` + applet install into `Makefile.linux-aarch64`
- [ ] Probe real H700 sysfs names (backlight, power_supply, codec card)
- [ ] Validate suspend/wake path before enabling real standby
- [ ] Effects routing decision (Lead/Agent 3)
- [ ] Target boot test with the applet loaded (needs image)
