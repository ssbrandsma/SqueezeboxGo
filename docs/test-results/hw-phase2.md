# HW Phase 2 results (privileged) — test results

Date: 2026-11-16. Branch: `hw/stock-poc2`.
Device: RG35XX H V4.0 (H700), stock Ubuntu 22.04 / kernel 4.9.170,
via `ssh rg35xxh` as user `muse` (key auth, **sudo working**).
Method: every claim below = pasted command + output (trimmed where noted).

## Summary

| Check | Status | Notes |
|---|---|---|
| sudo + groups | PASS | `sudo -n whoami` → root; muse += video,audio,input |
| stock-probe.sh privileged | PASS + BUG | exit 0, tarball verified; §90 quoting bug reproduced exactly |
| framebuffer truth | PASS | live 1280x1024x16, single-buffer; panel path 640x480 (DE scales) |
| fb write/readback | PASS | reversible 1-line pattern test, restored byte-identical |
| input nodes/uinput/evtest | PASS | by-path confirmed, uinput root-only, evtest 1.33 present |
| evtest command list | READY | prepared for owner, NOT run (needs fingers) |
| audio snapshot | PASS | cards/mixer/hw_params/owner all captured |
| ALSA owner | PASS | dmenu.bin PID 2434 / TID 2461 holds pcmC0D0p (XRUN, 44.1k S16LE) |
| sleep path | PASS | vendor→mod pwr_new.sh mapped; lockfile inhibit code-verified, live-fire pending (timer dormant) |
| frontend stop/restart | PASS | stop 0.25s + slow dmenu exit (poll 60s); start 0.10s, back ~5s; ALSA freed/held; SSH alive |
| Jammy tarball on device | PASS | sha256 673ec5ee…02baa MATCH, sp-stage extract intact |
| jive launch | NOT RUN | by design (needs fbcon SDL build + human eyes) |

## sudo (PASS)

```text
$ ssh rg35xxh 'sudo -n whoami; ...; id muse'
root
---
SUDO_OK
muse : muse sudo
uid=1000(muse) gid=1000(muse) groups=1000(muse),27(sudo)
```

Groups added (reversible, recommended in Phase 1 handoff; re-login applies,
each ssh is a new login so effective immediately):

```text
$ ssh rg35xxh '... sudo -n usermod -aG video,audio,input muse && ... id muse'
GROUPS_OK
uid=1000(muse) gid=1000(muse) groups=1000(muse),27(sudo),29(audio),44(video),107(input)
```

Restore (if ever wanted): `sudo deluser muse video audio input` — kept,
it is the documented PoC posture.

## stock-probe.sh privileged re-run (PASS + BUG proven)

Fresh `stock/probe/stock-probe.sh` from main pushed to device
(md5 `9117ee1576fdc34b7d19e1dd92802906` both sides), run as root:

```text
$ ssh rg35xxh 'cd ~/squeezebox-dev && sudo -n sh stock-probe.sh >probe-run2.log 2>&1; ...'
exit=0
-rw-r--r-- 1 root root 53058 ... stock-probe-20261116T122711Z-ANBERNIC.tar.gz
```

Run log (`docs/hw-evidence/probe-run2-privileged.log`):

```text
stock-probe: writing to ./stock-probe-20261116T122711Z-ANBERNIC
stock-probe: tarball: ./stock-probe-20261116T122711Z-ANBERNIC.tar.gz
5911301f6e8542bc5d40b71db6334cc19bb79530d06286490b71474829ffa0a8  ./stock-probe-20261116T122711Z-ANBERNIC.tar.gz
stock-probe: files: 11 section files
```

Tarball committed under `docs/hw-evidence/`, `sha256sum -c` → OK on host.

### §90 quoting question: RESOLVED — real bug, one missing quote

Section `90-frontend-hunt.txt`, still failing under sudo, exact bytes:

```text
===== frontend-like processes
$ sh -c ps auxf 2>&1 | grep -i -E '[e]mulat|...|[s]ddm || echo 'no obvious frontend string in ps output'
sh: 1: Syntax error: Unterminated quoted string
[exit=2]
```

Root cause (`stock/probe/stock-probe.sh` line 244): the `grep -i -E '...`
pattern is never closed after `[s]ddm`, so the pattern swallows `|| echo`
and the final `'` opens an unterminated quote. Proof on device with the
verbatim inner command vs the one-char fix (files `q-buggy.sh` /
`q-fixed.sh` in `~/squeezebox-dev`, kept for the probe owner):

```text
--- buggy file content:
ps auxf 2>&1 | grep -i -E '[e]mulat|[s]ddm || echo 'no obvious frontend string in ps output'
--- buggy run:
q-buggy.sh: 2: Syntax error: Unterminated quoted string
exit=2
--- fixed run:            # single ' added after [s]ddm
no obvious frontend string in ps output
exit=0
```

Full fixed line-244 pattern runs exit=0 and matches only itself (no real
frontend process contains those keywords; dmenu coverage stays manual as
in Phase 1). **Fix for probe owner: add the closing `'` after `[s]ddm`
on line 244.** Script otherwise clean (exit 0, 11 sections).

## framebuffer truth (PASS)

No `fbset` on device; used python3 ioctl (`~/squeezebox-dev/fbinfo.py`,
kept on device; logic pasted below in Reproduce). `/dev/fb0` opens as
`muse` (video group) — no sudo needed for reads.

`FBIOGET_VSCREENINFO`:

```text
xres=1280 yres=1024 xres_virtual=1280 yres_virtual=1024 xoffset=0 yoffset=0
bpp=16 grayscale=0
red_o=0 red_l=0 ... (ALL bitfield offsets/lengths zero — driver reports none)
nonstd=0 activate=0 height_mm=94 width_mm=150 accel_flags=0
pixclock_ps=9369 left_margin=224 right_margin=32 upper_margin=32 lower_margin=4
hsync_len=136 vsync_len=4 sync=0 vmode=0 rotate=0 colorspace=0
```

`FBIOGET_FSCREENINFO`:

```text
fix_id=b'\x00...' (empty) smem_start=0xff800000 smem_len=0x708000
type=0 (packed) visual=2 (TRUECOLOR) xpanstep=1 ypanstep=1 ywrapstep=0
line_length=0xa00 (2560) mmio: none accel=0 caps=0
```

sysfs agrees: `virtual_size` 1280,1024, `bits_per_pixel` 16, `stride` 2560,
modes `U:1280x1024p-59` + `U:640x480p-59`, `/proc/fb` = `0 ` (empty name).

### 1280x1024-vs-640x480: RESOLVED

- The LIVE `/dev/fb0` really is 1280x1024x16 (stride 2560 = 1280×2,
  RGB565 implied; driver reports zeroed bitfields so **UI must assume
  RGB565, not trust the bitfields**).
- The stale first-boot `fb.cfg` dump (640x480x32, yoffset 480) is NOT the
  current state — vendor stack reconfigures to 1280x1024 later in boot.
- The PANEL path is 640x480: `disp/attr/sys` (now readable via sudo) shows
  `mgr0: 640x480 ... lcd output ... 640x 480`, `xres`/`yres` nodes read
  640/480, and the only live layer is `ch[1] lyr[0] ... fb[640,480]`
  at `ff000000/ff04b000/ff096000` (3×307200 = triple 640x480 planes).
- fb0's own memory (`0xff800000`, len `0x708000` ≈ 2.8 frames) is NOT the
  visible layer right now.
- Double-buffer via y-pan: NO — `yres_virtual == yres` (1024), yoffset 0;
  `ypanstep=1` allows panning but there is no second frame inside the fb.
- Frame math: (1280+224+32+136)×(1024+32+4+4) @9369ps ≈ 60 Hz. Panel runs
  59.8 fps per disp.

**PoC consequence: drawing to /dev/fb0 is necessary but not proven
sufficient — the visible layer is a separate 640x480 disp surface.
Whether SDL1.2-fbcon output reaches the panel needs the human-observed
pattern test (§handoff item 2).**

### fb write/readback (PASS, reversible)

One scanline saved → red `0xF800` line written → read back → restored:

```text
6cf7f5835e416cbacc871e8853257654  -              # readback == written red line
6cf7f5835e416cbacc871e8853257654  /tmp/fb0-red.bin
a371492f16c0940507435909603efe88  -              # readback == saved original
a371492f16c0940507435909603efe88  /tmp/fb0-save.bin
```

Writes used sudo (muse+video could also write; reads need no sudo).
Live full-frame hash for reference: `8354dcaa...` (2.6 MB read as muse).

## input (PASS + prepared list)

```text
$ ls -l /dev/input/by-path/
platform-dierct-keys-polled-event -> ../event2     # vendor typo intact
platform-soc@03000000:gpio_keys-event-joystick -> ../event1
platform-soc@03000000:gpio_keys-joystick -> ../js0
platform-twi5-platform-axp2101-pek.0-event -> ../event0   # note: axp2101 in path
$ ls -l /dev/uinput; command -v evtest
crw------- 1 root root 10, 223 ... /dev/uinput     # root-only: injection needs sudo
/usr/bin/evtest                                     # evtest 1.33 present
crw-rw---- 1 root input ... event0/1/2              # muse now in input group: can evtest w/o sudo
```

Per instructions evtest was NOT run (needs human fingers; also grabs the
device). Exact command list for the owner (§handoff item 1).

## audio (PASS)

```text
$ aplay -l
card 0: audiocodec ... device 0 ... Subdevices: 0/1   # OCCUPIED
card 2: ahubhdmi   ... device 0 ... Subdevices: 1/1   # free
$ aplay -L   # null bluealsa default playback_hp playback_hdmi hw/plughw/sysdefault/dmix both cards
$ amixer -c0 scontents
LINEOUT [on]; OutputL Mixer DACL [on]; OutputL Mixer DACR [off];
OutputR Mixer DACL [off]; OutputR Mixer DACR [on]; SPK [on];
digital volume 63/63; lineout volume 31/31; tx hub mode Off
```

Full outputs committed in `docs/hw-evidence/audio-phase2.txt`.

PCM owner (now with sudo, cross-checked three ways):

```text
$ cat /proc/asound/card0/pcm0p/sub0/status /proc/asound/card0/pcm0p/sub0/hw_params
state: XRUN
owner_pid   : 2461
...
access: RW_INTERLEAVED / format: S16_LE / channels: 2 / rate: 44100
period_size: 1024 / buffer_size: 4096
$ sudo -n fuser -v /dev/snd/*
/dev/snd/pcmC0D0p:   root  2434 F.... dmenu.bin
$ ps -T -p 2434 -o pid,tid,comm
2434    2434 dmenu.bin ... 2434    2461 dmenu.bin   # TID 2461 ∈ PID 2434. CONFIRMED
```

dmenu's audio thread holds pcmC0D0p in XRUN since boot trigger
(`trigger_time` = April-2022 device-clock era = boot with stale RTC).
Stop the frontend service before any exclusive `hw:` open (validated §frontend).

## sleep (PASS — characterized; live-fire honestly scoped)

Full pasted evidence: `docs/hw-evidence/sleep-phase2.txt`.

Chain: dmenu idle timer (`++++ timer to sleep`, calls `%s auto`) →
`/mnt/vendor/ctrl/pwr_new.sh` → mod `/mnt/mod/ctrl/pwr_new.sh` →
`echo -n mem > /sys/power/state`. Both scripts guard on
`/tmp/.power_key` (skip suspend while it exists). Config
`power.hdmi=1/power.key=2/power.lock=0`, live `HDMI=0` → auto path
sleeps. These two files are the ONLY `power/state` writers on the
system (recursive grep over vendor/mod/usr-local/etc).

History: 3 suspend cycles early in boot, ~86 s apart (`Suspended for
7.123 seconds` = Phase 1's 7.1 s), then NOTHING for 36+ min — the idle
timer is currently dormant (owner activity or dmenu UI state; HDMI=0
so it is not the HDMI guard). Wake IRQ 321 = `axp2202_irq_chip` via
NMI = physical power button; no RTC wakealarm armed; no autosleep
node; systemd targets masked; logind `HandlePowerKey=ignore`.

What was NOT live-tested, and why: forcing a suspend with no auto-wake
strands the device until a human presses power, and the dormant timer
cannot validate an inhibit either. So:

- `systemd-inhibit`: NOT APPLICABLE by mechanism (direct sysfs write,
  zero logind/systemd mediation; only a NetworkManager `delay` inhibitor
  exists). No live test needed — evidence is the call chain.
- Lockfile inhibit (`sudo touch /tmp/.power_key`, restore `sudo rm -f`):
  code-path VERIFIED in both scripts, live-fire PENDING (needs the timer
  firing or a human on wake standby). This is the documented reversible
  inhibit for future long PoC runs — nothing is disabled permanently.
- Stopping the frontend to stop auto-suspend: untestable live while the
  timer is dormant, but the mechanism (dmenu is the sole `auto` caller)
  says it works; the stop procedure itself is validated below.

dmenu idle config: `/mnt/data/dmenu/dmenu_attr.ini` is 140 bytes BINARY
(not a timeout file); no text config on the system mentions autosleep;
timeout is compiled-in or binary state. Caller + `auto` arg confirmed
via dmenu.bin strings.

## frontend stop/restart (PASS — with one real finding)

Full pasted log: `docs/hw-evidence/frontend-stopstart-phase2.txt`.

- STOP: `sudo systemctl stop launcher.service` → exit 0 in **0.25 s**,
  service `inactive`. Respawn loop (`loadapp.sh`) dead immediately —
  no respawn race. BUT **dmenu.bin PID 2434 was still alive + holding
  ALSA right after stop-exit=0**: SIGINT/SIGUSR1 from the stop path
  shut it down SLOWLY (gone + ALSA free by the next check ~45 s later;
  a follow-up SIGTERM found no process — nothing stronger was needed).
  PROCEDURE: after stop, poll `pidof dmenu.bin` up to 60 s before
  exclusive ALSA/fb work.
- SETTLE 25 s: service inactive, no dmenu, no loadapp, card0 `1/1`
  (ALSA FREE), SSH alive. Zero respawn (`Restart=no`).
- START: `sudo systemctl start launcher.service` → exit 0 in **0.10 s**,
  service `active`. No SSH stall (loadapp's NetworkManager restart kept
  the wlan0 link). dmenu back after **~5 s** (fresh PID 10506 under fresh
  loadapp 10392); ALSA re-held by the new PID (card0 `0/1`); disp layer
  back with identical config (ch1/lyr0 640x480, fps 59.5, backlight 140).
- Preconditions verified safe: `boot_mode=0` (no charger-mode poweroff
  path), no `/mnt/mmc/gpio_keys_polled.ko` (no insmod), no
  `/mnt/mod/.last` (no last-game hijack), mod `autostart` tail fully
  idempotent (all `[ ! -f ]`/`[ ! -L ]` guarded). Side note: autostart
  explains the stale `fb.cfg` — dumped ONCE at mod install when fb was
  640x480x32; live fb has since moved to 1280x1024x16.
- Footnote: `pidof` never sees shell scripts (`loadapp.sh` invisible to
  it, before AND after); use `ps`/`pgrep -f` for the loop.

## PoC staging (PASS — ready except video route + fingers)

```text
$ sha256sum ~/squeezebox-dev/squeezeplay-aarch64-9.0.0.tgz
673ec5eec78ca5127d7202951d292b194f47bc22747c9a12a8f82069bcc02baa  MATCH
$ find ~/squeezebox-dev/sp-stage -maxdepth 5 -name 'jive*'
.../sp-stage/opt/squeezeplay/bin/jive_alsa
.../sp-stage/opt/squeezeplay/bin/jive        # extract intact
```

jive NOT launched per instructions. Readiness: binary staged + hash OK,
stop/ALSA-free procedure validated, groups fixed, evtest present. Gating:
(1) stock video = SDL1.2-fbcon build still to be produced (Core/UI), and
(2) the fb0-visibility question needs human eyes (handoff item 2), and
(3) input map needs the evtest capture (handoff item 1).

Device clock note: device TZ is UTC+1 (local `ps`/`ls` read 13:xx while
epoch/`date -u` read 12:xx UTC). All times above are consistent; no NTP
jump mid-session. dmesg suspend-count changed 2→1 across the test by
ring-buffer wrap only.

## Handoff — needs the human

1. **evtest capture** (fingers): exact command list + expected-code table
   in `docs/hw-evidence/evtest-handoff.md`. Covers event1 (verify DT map:
   ABXY 304-307, L1/R1 308/309, L2/R2 314/315, hat dpad 16/17, …),
   event2 discovery (unknown set), event0 query-only (power = hands off).
2. **fb0 visibility test** (eyes): with dmenu STOPPED (procedure above),
   run as root `python3 -c` mmap fill of `/dev/fb0` with solid red
   (`0xF800` × 1280 × 1024, 16 bpp — script on request, or reuse the
   1-line `dd` pattern from §fb extended to full frame), then LOOK:
   full red screen = fb0 is the visible path (SDL1.2-fbcon viable);
   unchanged dmenu/frozen frame = visible layer is disp-direct (PoC
   needs the disp route or FBIOPAN/layer attach work). Restore with
   `sudo systemctl start launcher.service`. ~2 min, fully reversible.
3. **0.3.0 second-card boot** (unchanged ask): UART log + LED observations
   from a ddr4 boot on the SECOND card.

## Reproduce

```sh
git checkout hw/stock-poc2
ls docs/hw-evidence/   # + stock-probe-20261116T122711Z tarball/.sha256,
                       #   probe-run2-privileged.log, audio-phase2.txt,
                       #   sleep-phase2.txt, frontend-stopstart-phase2.txt,
                       #   evtest-handoff.md, scripts-phase2/ (fbinfo, fbfix, q-*)
cat docs/test-results/hw-phase2.md   # this file
```

Device footprint added this phase (all under `~/squeezebox-dev`, ~200 KB):
`stock-probe.sh` (fresh), probe-run2 outputs, `fbinfo.py`, `fbfix.py`,
`q-buggy.sh`, `q-fixed.sh`, `q-full-fixed.sh`, `/tmp/fb0-{save,red}.bin`
(auto-cleaned). Only persistent system change: muse += video,audio,input
(restore: `sudo deluser muse video audio input`).
