# HW Phase 3 results (headless PoC validation) — test results

Date: 2026-11-16. Branch: `hw/stock-poc3`.
Device: RG35XX H V4.0 (H700), stock Ubuntu 22.04 / kernel 4.9.170,
via `ssh rg35xxh` as user `muse` (key auth, sudo working).
Method: every claim below = pasted command + output (trimmed where noted).
Human-gated items (visibility, evtest fingers, ear check) explicitly NOT
claimed — see Handoff.

## Summary

| Check | Status | Notes |
|---|---|---|
| fbcon SDL deploy | PASS | sha 3924a625 MATCH on device; shadow dir; ldd resolves fbcon first |
| Jammy tarball intact | PASS | sha 673ec5ee MATCH; sp-stage jive+jive_alsa present |
| fb0 write/readback | PASS | full-frame (2.6 MB) pattern, byte-identical, non-degenerate proof |
| visibility | NOT CLAIMED | human red-fill watch still required (Phase 4) |
| frontend stop | PASS | stop 0.19 s, dmenu gone ~10 s, card0 free |
| audio chain (aplay) | PASS | exit 0, RUNNING, S16LE/2ch/44.1k, zero XRUN lines; ear check = human |
| headless jive (fbcon) | PASS | main loop reached: 22/s screen-pump heartbeat, rendered frame, clean SIGTERM |
| dummy control | PASS | exact failure: `Video mode not supported: 0x0`, exit 255, pre-watchdog |
| SysV IPC absence | FINDING | CONFIG_SYSVIPC=n; jive sem/shm calls fail noisy-but-harmless (core unaffected) |
| fb mode PUT quirk | FINDING | zeroed-timings PUT → sticky 512x384x32 report; valid-timings PUT restores 1280x1024x16 |
| chvt hang | FINDING+WARN | VT_WAITACTIVE wedges (dmenu VT_PROCESS no-ack); DO NOT chvt; orphans cleaned |
| frontend restore | PASS* | dmenu running, stock pixels, vinfo 1280x1024x16, SSH alive; ALSA free-but-functional (hold unresolved, see §restore) |
| LIVE-COLOR-TEST script | READY | `stock/bundle/color-fill.py`, syntax-checked, NOT run |

## fbcon SDL deploy (PASS)

```text
$ scp /tmp/sdl-fbcon/out/lib/libSDL-1.2.so.0.11.4 rg35xxh:~/squeezebox-dev/libSDL-fbcon.so.0.11.4
scp_exit=0
$ ssh rg35xxh 'cd ~/squeezebox-dev && sha256sum libSDL-fbcon.so.0.11.4 squeezeplay-aarch64-9.0.0.tgz; ...'
3924a6254c1c4c9690b7d7f3905465b84f7dd134b372155909eca02d6f3f8d4a  libSDL-fbcon.so.0.11.4
673ec5eec78ca5127d7202951d292b194f47bc22747c9a12a8f82069bcc02baa  squeezeplay-aarch64-9.0.0.tgz
libSDL-fbcon.so.0.11.4: ELF 64-bit LSB shared object, ARM aarch64, ...
.../sp-stage/opt/squeezeplay/bin/jive
.../sp-stage/opt/squeezeplay/bin/jive_alsa
```

Shadow select (tarball copy never overwritten):

```text
$ ... 'ln -sf ../libSDL-fbcon.so.0.11.4 fbcon-lib/libSDL-1.2.so.0 && ... ldd ./jive | grep ...'
libSDL-1.2.so.0 -> ../libSDL-fbcon.so.0.11.4
libSDL-1.2.so.0 => /home/muse/squeezebox-dev/fbcon-lib/libSDL-1.2.so.0 (...)
```

## fb0 write/readback (PASS, reversible, headless only)

Geometry (live ioctl, matches Phase 2): 1280x1024, xvirt=1280
yvirt=1024, bpp=16, stride 2560. Scripts: `docs/hw-evidence/
scripts-phase3/fb-phase3.py` (gradient) and `fb-phase3b.py`
(inverted gradient + red marker rows 100–103).

Run 1 (found an API quirk — `mmap.flush()`/msync on fb0 → EINVAL;
harmless, writes still land; dropped from later runs):

```text
GEOM xres=1280 yres=1024 xvirt=1280 yvirt=1024 xoff=0 yoff=0 bpp=16
ORIG sha=6de7493c5c90f643357c268fbaaf461c1567e0334e4948023ce17268403aa37a len=2621440
PAT sha=d72978b0ae7789df4f5b53b483e87662cc49a6a9526fc83486bda34317e188c5
OSError: [Errno 22] Invalid argument   # mm.flush() — msync unsupported on fb mmap
```

Run 2 (ORIG == run-1 PAT proves run-1's write landed in fb memory):

```text
ORIG sha=d72978b0ae7789df4f5b53b483e87662cc49a6a9526fc83486bda34317e188c5 len=2621440
PAT sha=d72978b0ae7789df4f5b53b483e87662cc49a6a9526fc83486bda34317e188c5
READBACK sha=d72978b0... IDENTICAL=True
RESTORE sha=d72978b0... IDENTICAL=True
```

Run 2b (non-degenerate: pattern differs from content):

```text
ORIG sha=d72978b0ae7789df4f5b53b483e87662cc49a6a9526fc83486bda34317e188c5
PAT sha=d24e75f3461e247d8c00a26358a05f326f1a9edac8f272306efca00bbe4c5c46 DIFFERS_FROM_ORIG=True
READBACK sha=d24e75f3... IDENTICAL=True
RESTORE sha=d72978b0... IDENTICAL=True
```

Full-frame (2.6 MB) write/readback/restore all byte-identical.
NO visibility claim: bytes proven in fb memory only.

## frontend stop + audio chain (PASS)

Stop (validated procedure; faster dmenu exit this round, ~10 s):

```text
stop_exit=0 (0.19 s), service inactive
t=5s dmenu=10506
dmenu gone after ~10s
card 0: audiocodec ... Subdevices: 1/1     # ALSA FREE
card 2: ahubhdmi   ... Subdevices: 1/1
```

Pre-play mixer (identical to Phase 2) + PCM `closed`. Conservative
volumes set (originals saved by inspection: 63/63 and 31/31):

```text
digital volume: Mono: 19 [30%]
lineout volume: Mono: 9 [29%]
```

Tone: `tonegen.py` (in scripts-phase3/) — 3 s 440 Hz sine at
-20 dBFS, stereo 16-bit 44.1 kHz WAV (529244 B). Playback:

```text
$ aplay -v -D plughw:CARD=audiocodec /tmp/tone3s.wav ...
=== status mid-play ===
state: RUNNING
owner_pid   : 11009
delay       : 17664 / avail 2816 (advancing hw_ptr/appl_ptr)
=== hw_params mid-play ===
access: RW_INTERLEAVED / format: S16_LE / channels: 2
rate: 44100 (44100/1) / period_size: 4096 / buffer_size: 20480
aplay_exit=0
```

Verbose log (`docs/hw-evidence/logs-phase3/aplay-phase3.log`, 26
lines): Plug PCM card 0, buffer 20480 / period 4096, start/stop
thresholds 20480 — **zero underrun/XRUN lines**. Mixer restored and
re-verified (`digital 63 [100%]`, `lineout 31 [100%]`); PCM `closed`
after. Raw ALSA playback on audiocodec PROVEN; human ear-confirm of
audible tone is a Phase 4 ask (stated, not claimed).

## headless jive boot (PASS — main loop reached)

Launch mechanics: `sudo -E` does NOT propagate LD_LIBRARY_PATH
(first attempt: exit 127 `libtolua++.so` missing — expected sudo
env-scrubbing). Root wrapper scripts set their own env (committed
under `docs/hw-evidence/scripts-phase3/`): `run-jive-fbcon.sh`
(probe video) and `run-jive-dummy.sh` (`SDL_VIDEODRIVER=dummy`).
HOME redirected to staging (`.../jive-home`) so no writes escape;
CWD = staged `bin/` (jive resolves share/ relatively).

### Attempt 1: fbcon probe, 60 s (exit 124 = still running)

```text
jive_exit=124
log: 1311 lines, ALL `semget/semctl: Function not implemented`
(1 semget + 1310 semctl, ~22/s)
```

Root cause (fully traced, not a jive failure):
- Stock kernel has `# CONFIG_SYSVIPC is not set` (from committed
  `docs/hw-evidence/stock-config.gz`).
- jive's hardware-watchdog keepalive (`src/squeezeplay/src/ui/
  platform_linux.c`: `watchdog_sem_get`/`watchdog_sem_keepalive`)
  uses SysV semaphores; `perror` on each failure.
- jive's own LOG_* lines were suppressed: log categories default
  `LOG_PRIORITY_OFF` (`log.c`) unless `logconf.lua` enables them —
  proven, then fixed with a staging `logconf.lua` (see control).

Why this proves the MAIN LOOP (source-order argument, all in
`src/squeezeplay/src/ui/jive_framework.c`):
- `jive_surface_set_video_mode()` (line ~318) runs BEFORE
  `watchdog_get()` (line ~364); a video failure calls `exit(-1)`.
  A 60 s run therefore passed SDL video init.
- The ~22/s spam comes from `jiveL_update_screen()` (line ~719),
  the main-loop screen pump (`watchdog_keepalive` per update),
  plus the decode thread loop (`decode.c`). 22/s == jive's
  "Using 22 frames per second" tick (seen in logged runs).

### Live probe of the running fbcon instance (all observed)

```text
JPID=11240, 2 threads (main + decode), 12 s+ uptime
fd 3 -> /dev/fb0, fd 4 -> /dev/tty2     # SDL opened fb + allocated a VT
maps: .../libSDL-fbcon.so.0.11.4        # OUR fbcon build, not dummy
fonts: FreeSans{,Bold}.ttf open (UI rendering active)
asound card0: closed                     # no PCM opened yet (nothing requested)
fb0 hash: 9cfd1076... != pattern d72978b0  # JIVE DREW (nothing else runs)
frame stable 5 s apart; log growth 22/s; SIGTERM -> clean quit
```

fb0 pixel analysis during the run: 547596/3686400 nonzero 16-bit
words, 2498 distinct colors, structured bands (content rows 0–384
and 704–1024, cleared gap 384–704) — a rendered UI, not noise.
(The exact layout reflects the 512x384x32 mode then active; see
§mode quirk. Geometry of proof: bytes changed + stable + jive is
the sole writer.)

### Control: SDL_VIDEODRIVER=dummy (exact failure, video separated)

```text
dummy_exit=255 in 0.129 s; 0 sem lines (dies before watchdog_get)
```

With logging enabled (`logconf.lua` in CWD), the exact stage:

```text
INFO ... jiveL_initSDL:252 0,0 8 bits/pixel ...   # dummy reports 0x0
INFO ... Hardware acceleration is not available
INFO ... Window Manager is not available
ERROR ... jive_surface_set_video_mode:901 SDL_SetVideoMode(0,0,8): Invalid width or height
ERROR ... jiveL_initSDL:322 Video mode not supported: 0x0
```

Full log: `docs/hw-evidence/logs-phase3/jive-dummy.log` (14 lines).
Conclusion: jive core boots iff video offers a mode; dummy offers
none → clean exit(-1) at the video stage. fbcon offers a mode →
main loop. Video and core cleanly separated.

### Logged fbcon run (25 s, startup lines captured)

Full log: `docs/hw-evidence/logs-phase3/jive-fbcon-logged.log`
(1733 lines). Key lines (deduped):

```text
INFO squeezeplay - JiveMain.lua:266 SqueezePlay version 9.0.0 r541
INFO ... jiveL_initSDL:252 512,384 32 bits/pixel ... [R<<16 G<<8 B<<0]
INFO ... Hardware acceleration is available
INFO ... jiveL_initSDL:330 Splash jive/splash.png 480x272 Screen 512x384
INFO squeezeplay - JiveMain.lua:590 select skin: WQVGAsmallSkin
ERROR audio.codec - decode_alsa_init:254 shmget error Function not implemented
ERROR squeezeplay - term_handler:332 SIGTERM squeezeplay 9.0.0 r541
WARN ... jiveL_process_events:482 JIVE_EVENT_QUIT
```

Notes: (1) 512x384x32 was inherited from the run-1 mode switch
(§mode quirk), not queried fresh. (2) Only 3 sem lines here: with
DEBUG logging on, the 25 s window was startup-dominated (widget
build); the 22/s heartbeat is proven by the unlogged runs. (3)
`shmget ENOSYS`: jive_alsa local-playback SHM is also unavailable
on this kernel — local decode-to-ALSA via jive needs a SysV-free
path (audio agent follow-up; raw ALSA itself is proven above).
(4) SIGTERM → handler → JIVE_EVENT_QUIT: clean signal behavior.

## fb mode PUT quirk (FINDING, restore proven)

jive run 1 left `/dev/fb0` reporting 512x384x32 (sysfs + ioctl
agree). Mechanism, fully traced:
- WQVGAsmallSkin requests `Framework:setVideoMode(480, 272, 0,
  false)` (`WQVGAsmallSkinApplet.lua:247`) — jive's SECOND
  SetVideoMode (non-fullscreen, skin-driven).
- SDL-1.2 fbcon `FB_SetVideoMode` memsets vinfo to zero and PUTs
  with only xres/yres/bpp + vesa timings (`SDL_fbvideo.c`).
- The sunxi driver answers 512x384x32 (sticky report). dmesg shows
  DISP `invalid fmt` chatter across these PUTs (non-fatal).
- `line_length` stays pinned at 2560 through every PUT; the frame
  memory layout never changes — only the vinfo report does.

Restore (proven twice, no reboot): PUT the full Phase-2 vinfo
(1280x1024x16 + vendor timings pixclock 9369, margins
224/32/32/4, sync 136/4, zeroed bitfields as stock):

```text
vinfo xres=1280 yres=1024 bpp=16     # after PUT, both attempts
```

dmenu behavior: dmenu's own startup PUT hits the same quirk
nondeterministically (1 flip observed in 2 clean starts from
1280x1024; third start stable — underdetermined vendor-driver
behavior, see §restore). dmenu repaints byte-identical pixels
(`6de7493c…`, the run-1 original) under EITHER vinfo report, so
the quirk is metadata-only for stock.

UI-agent consequence: jive/SDL may request one size and GET
another — always re-query after SetVideoMode; our 640x480 skin's
request must be verified live, not assumed.

## frontend restore (PASS* — read the asterisk)

Final cycles: stop (poll ≤60 s) → PUT-restore vinfo → start →
verify. End state after the last cycle:

```text
dmenu=12826 active=active (fresh loadapp chain, 1-2 s CPU over minutes = idle)
vinfo xres=1280 yres=1024 bpp=16
fb0 first-2.6MB sha = 6de7493c5c90f643...  # == run-1 original: pixel-perfect stock UI
mixer: digital 63 [100%], lineout 31 [100%]
SSH alive; no stray jive/stdbuf/timeout/aplay processes
```

Asterisks (all documented, none blocking PoC):
- **ALSA free, not re-held.** Fresh dmenu instances (11839, 12239,
  12826) never opened ALSA (no asound libs mapped, `fuser`
  /dev/snd/* empty, card0 1/1 `closed`) — unlike the boot
  instance (Phase 1/2: held pcmC0D0p in XRUN) and unlike Phase
  2's restarted 10506 (reported re-held). ALSA itself is proven
  functional (our aplay test). Cause unresolved headlessly
  (jingle path? VT-dependent init? — see next). A reboot
  replays the true boot path and settles it (pending below).
- **Active VT stuck at tty2** (stock boot = tty1). jive's SDL
  activated tty2 and later kills left it there. `chvt` HANGS
  (VT_WAITACTIVE never completes — dmenu takes its VT,
  VT_PROCESS without ack; hangs even with dmenu dead, i.e. the
  switch Wedged kernel-side). Two stuck chvt chains were
  cleaned (`kill -9`, verified gone). **DO NOT chvt on this
  device while dmenu runs.** Reboot clears it.
- `/tmp/.power_key` sleep-inhibit lockfile was used for the
  final window (Phase-2-verified mechanism); removed by the
  pending reboot (else `sudo rm -f` it — normal stock sleeps).

## Device footprint added in Phase 3

Under `~/squeezebox-dev` (~600 KB): `libSDL-fbcon.so.0.11.4`,
`fbcon-lib/` symlink, `fb-phase3{,b}.py`, `run-jive-{fbcon,
dummy}.sh`, `logs-phase3/` (5 jive logs), `jive-home/` (jive
settings). In sp-stage bin (staging only): `logconf.lua`
(CWD-found diagnostic logging for jive). In /tmp (auto-wiped on
reboot): `tone3s.wav`, `tonegen.py`, `aplay-phase3.log`,
`dummy-direct.log`. No system writes (no /etc, /usr, units,
masks). Only persistent system change remains Phase 2's
`muse += video,audio,input`.

## Reboot normalization (PASS — true stock, all asterisks cleared)

After evidence commit, `sudo -n reboot`; device back on SSH ~2 min
later (up 1 min, load settling). Single-shot verification (beat the
idle-sleep timer; no further device commands after):

```text
ALIVE, up 1 min; launcher.service active; dmenu=2443 (boot instance)
dmenu fds: /dev/fb0 + /dev/tty2 (= active VT: boot dmenu takes tty2
  and activates it; the tty3-taking was restart-path-only)
card 0: Subdevices: 0/1; /dev/snd/pcmC0D0p: root 2443 F.... dmenu.bin
  => ALSA HELD by boot dmenu (boot-path jingle/init; restart-path
  dmenus simply never open it — mystery solved, no session damage)
mixer digital 63 [100%]; vinfo xres=1280 yres=1024 bpp=16 (boot state)
fb0 first-2.6MB sha = 6de7493c... (stock UI pixels, 4th reproduction)
/tmp/.power_key gone (wiped; stock auto-sleep re-armed)
~/squeezebox-dev staging intact (all Phase 1-3 files + logs persist)
active VT = tty2 (IS the boot state — earlier tty1 readings were
  post-boot drift; the wedged chvt-3 switch was reboot-cleared)
```

Device ends in TRUE stock state: frontend running, ALSA held,
vinfo/mixer/pixels at boot values, SSH alive, only footprint =
`~/squeezebox-dev` staging + `muse` groups (both documented PoC
posture). No system writes ever made.

## Handoff — needs the human (unchanged + 1 new)

1. **Red-fill watch** (eyes, ~2 min): run the coordinated
   LIVE-COLOR-TEST — `stock/bundle/color-fill.py` (stop
   frontend, `sudo python3 color-fill.py`, report per-color
   coverage, script self-restores + restarts frontend).
   Decides the fb0-visibility question Phase 2 posed.
2. **evtest capture** (fingers): unchanged —
   `docs/hw-evidence/evtest-handoff.md`.
3. **Ear check** (ears): replay `/tmp/tonegen.py`-generated
   440 Hz tone at ≤30% (`aplay -D plughw:CARD=audiocodec`) and
   confirm audible output; exact procedure in §audio above.
4. **0.3.0 second-card boot** (unchanged ask): UART log + LED
   observations from a ddr4 boot on the SECOND card.

## Reproduce

```sh
git checkout hw/stock-poc3
ls docs/hw-evidence/logs-phase3/ docs/hw-evidence/scripts-phase3/
cat docs/test-results/hw-phase3.md   # this file
```
