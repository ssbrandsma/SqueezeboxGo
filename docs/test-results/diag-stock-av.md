# diag-stock-av (TRACK B2): stock graphics/input/audio path — analysis evidence

Branch: `diag/stock-av` (isolated worktree, base main @ `ca32f0c`).
Date: 2026-11-16. No device access (all device commands are user-run probes).

Method: read-only source inspection of the pinned tree on this branch —
`docs/hardware.md` (verified inventory), `ui/README.md`,
`squeezeplay/configuration/Makefile.linux-aarch64` (SDL flags),
`build/image/stage-payload.sh` (SDL shadowing), `ui/vendor/*`,
`ui/tests/sdl_smoke.c`, `ui/input/evdev2jive.c` + `rg35xxh.map`,
`audio/ALSA_PATH.md`, `audio/alsa/{asound.conf,mixer-controls.md,
capability-detect.sh}`, `audio/arbiter/*`, `audio/tests/topology-probe.sh`,
`platform/rg35xx-h/services/squeezeplay.sh`, `ui/BRINGUP.md`.
New files only; no shipped target code path modified.

## Deliverables (all new files)

- `ui/stock-fbcon-BUILD.md` — SDL1.2-fbcon route, exact configure flags,
  current-build gap, vendor-SDL detection, fbset/vinfo probes.
- `ui/stock-input.md` — by-name evdev discovery, per-device handling
  (ANBERNIC-keys / dierct-keys-polled / axp2202-pek), probe commands.
- `audio/stock-audiocodec.md` — stock ALSA device strings, mixer-init
  template, mandatory owner-identification pre-flight, arbiter-vs-foreign-
  holder analysis.
- This file — evidence + stock-probe.sh command list for the bundle agent.

## Finding 1 (framebuffer): stock needs real SDL-1.2.15 fbcon; we ship none

- Stock has `/dev/fb0` only, no `/dev/dri` (`docs/hardware.md:49-56`).
- Our shipped video chain is sdl12-compat 1.2.78 on SDL2 ≥ 2.30 kmsdrm
  (`ui/README.md:5-6,37-39`), whose only X-less driver needs `/dev/dri`.
- Our SDL-1.2.15 build is link-ABI-only: Makefile comment
  *"Dummy/fbcon video stay enabled so configure always finds >=1 video
  driver"* (`squeezeplay/configuration/Makefile.linux-aarch64:180-184`),
  and `stage-payload.sh` step 3 **deletes** the built `libSDL-1.2.so.0*`
  and installs compat + SDL2 2.32.10 instead
  (`build/image/stage-payload.sh:87-97`). Net: nothing shipped opens
  `/dev/fb0` — verified by reading, no device needed.
- Recipe written: `--enable-video-fbcon=yes` forced, audio/joystick off
  (Jive uses `jive_alsa` + `evdev2jive`), verify via configure's
  `Video drivers:` line + `SDL_VIDEO_DRIVER_FBCON` in `SDL_config.h`;
  runtime `SDL_VIDEODRIVER=fbcon SDL_FBDEV=/dev/fb0`; smoke via existing
  `ui/tests/sdl_smoke.c` rebuilt against the fbcon lib.
- HW-gated: fb geometry (1280x1024 virtual vs 640x480 LCD — xres/yres,
  offsets, bpp/RGB order, `line_length`, `visual`, `rotate`), `fbset`
  presence, vendor SDL presence. Probes specified (§probe list, groups
  G1–G3); python3 ioctl fallback included for `fbset`-absent stock.

## Finding 2 (input): by-name mechanism already exists; stock needs new names + codes

- `evdev2jive` matches by `EVIOCGNAME` substring from `device` map lines
  (`ui/input/evdev2jive.c:683-724`); shipped map matches mainline
  `gpio-keys`/`adc-joystick` (top of `ui/input/rg35xxh.map`).
- Stock map must match `ANBERNIC-keys` + `dierct-keys-polled` (exact
  vendor spelling, typo included) and leave `axp2202-pek` to init by
  default (PMIC power-key owns hardware power behavior).
- Mainline code tables (`BTN_*`, `ABS_*` 0..4096) are NOT assumed for the
  vendor driver — stock map is written only from the `evtest` capture
  template in `ui/stock-input.md` §4. HW-gated: real codes, ABS
  ranges/polarity, `/dev/uinput` presence, `evtest` presence, whether the
  vendor console consumes uinput keys under SDL1.2-fbcon.

## Finding 3 (audio): stock card naming breaks mainline assumptions; PCM was busy

- Stock: cards `audiocodec`/`ahubdam`/`ahubhdmi`, aliases per `aplay -L`
  (`playback_hp`, `playback_hdmi`, `bluealsa`); start `jive_alsa` at
  `plughw:CARD=audiocodec,DEV=0`, narrow to `hw:` after hw-params dump.
- Mainline `asound.conf` aliases/pinning do not apply; stock keeps its
  own ALSA config (read, don't overwrite).
- `capability-detect.sh` matches `H616 Audio Codec`/`sun4i-codec` and
  reports `internal.card=-1` on stock (expected: stock naming, not
  missing hardware); `topology-probe.sh` mainline assertions
  (`H616AudioCodec`, `CDC PCM`, no `stream0`) are expected to FAIL on
  stock — a correct mainline-vs-vendor discriminator.
- Mandatory pre-flight before any stock playback: PCM `status`
  (`state`/`owner_pid`) + `fuser -v /dev/snd/*` + `lsof`, then identify
  the holder service. Never kill stock daemons from scripts.
- Arbiter analysis: `audio-owner` tracks only self-registered claims
  (PID+starttime liveness, `audio/arbiter/DESIGN.md:29-36`), so stock
  daemons are invisible to it — `status: free` with a busy PCM is the
  expected failure mode. Stock launchers must gate acquire on the
  kernel-domain check (fuser-empty); `force-release` cannot free foreign
  holders. Wrapper sketch in `audio/stock-audiocodec.md` §5.

## Probe-command list for the bundle agent (stock-probe.sh)

All read-only except where marked `[eyes]` (needs a human watching the
panel) or `[press]` (needs a human pressing controls). Keep the existing
UART root-shell, second-card-safe, reversible rules: probe script must
not write outside `/tmp`, must not kill/mute/reconfigure anything, must
not overwrite stock config.

```sh
# --- G0 environment ---
uname -a; cat /etc/os-release | head -3
ls /dev/dri 2>&1 || echo "no /dev/dri"
ls -l /dev/fb* /dev/snd/ /dev/input/ 2>&1
cat /proc/fb; cat /proc/asound/cards; cat /proc/asound/devices
command -v fbset evtest amixer aplay python3 fuser lsof udevadm 2>&1

# --- G1 graphics geometry (stock-fbcon-BUILD.md §5) ---
cat /sys/class/graphics/fb0/name
fbset -i -fb /dev/fb0; fbset -s -fb /dev/fb0   # if fbset present
for f in virtual_size bits_per_pixel stride modes mode pan rotate state blank; do
  printf '%s: ' "$f"; cat /sys/class/graphics/fb0/$f 2>&1 | head -5
done
# + python3 FBIOGET ioctl fallback if fbset absent (see ui/stock-fbcon-BUILD.md §5d)

# --- G2 vendor SDL (stock-fbcon-BUILD.md §4) ---
ldconfig -p | grep -i sdl || echo "no SDL in ldconfig cache"
dpkg -l | grep -i sdl || echo "no SDL dpkg packages"
ls -l /usr/lib/aarch64-linux-gnu/libSDL* /usr/lib/libSDL* /usr/local/lib/libSDL* 2>/dev/null
ls /mnt/vendor /mnt/data 2>/dev/null
find /mnt/vendor /mnt/data /opt /usr/local -name 'libSDL*' 2>/dev/null

# --- G3 [eyes, later phase] fbcon smoke: run only after G1 is understood ---
# SDL_VIDEODRIVER=fbcon SDL_FBDEV=/dev/fb0 ./sdl_smoke_fbcon ; report panel result

# --- I1 input inventory (stock-input.md §4a-4c) ---
cat /proc/bus/input/devices
ls -l /dev/input/by-id/ /dev/input/by-path/ 2>&1
for ev in /dev/input/event*; do echo "== $ev";
  udevadm info --query=all --name="$ev" 2>/dev/null | grep -E 'ID_INPUT|DEVNAME|ID_PATH'; done
ls -l /dev/uinput /dev/input/uinput 2>&1

# --- I2 [press] live code capture (stock-input.md §4d) ---
# evtest <ANBERNIC-keys node>: press every control once, record KEY/BTN + ABS min/max/idle/polarity
# evtest <dierct-keys-polled node>: press its keys, record codes
# evtest <axp2202-pek node>: ONE short power tap only (never long-press), record code

# --- A1 audio inventory (stock-audiocodec.md §4) ---
aplay -l; aplay -L
amixer -c 0 scontents
aplay -D hw:0,0 --dump-hw-params /dev/null 2>&1 | head -40
cat /proc/asound/card0/pcm0p/info
cat /etc/asound.conf 2>/dev/null; ls /usr/share/alsa/alsa.conf.d/ 2>/dev/null

# --- A2 owner pre-flight (stock-audiocodec.md §3) ---
grep -H . /proc/asound/card*/pcm*p/sub*/status 2>/dev/null | grep -E 'state|owner_pid'
fuser -v /dev/snd/* 2>&1
lsof /dev/snd/* 2>&1 || echo "(lsof absent)"
# for each holder PID: ps -o pid,ppid,comm,args -p <PID>
```

## Unresolved (all HW-gated, need user-run probes)

1. fb geometry truth (xres/virtual/offsets/bpp/RGB order/stride/visual/
   rotate) — blocks stock video mode choice.
2. Vendor SDL presence/version/fbcon support — fastest-stock-path question.
3. Real stock evdev codes + ABS ranges/polarity — blocks stock `.map`.
4. `/dev/uinput` + `evtest` presence on stock.
5. Stock ALSA holder identity + `aplay -L` aliases + hw-params matrix +
   exact `scontents` names — blocks mixer init + device-string choice.
6. Whether the vendor console consumes uinput keys (input E2E under
   fbcon) — needs phases after 1–5.
```

Verification performed on host (no device): branch created from
`ca32f0c`; four new files added, zero tracked files modified
(`git status` shows only the four new paths); shell blocks are
probe-only (no writes outside `/tmp`, no kills, no config overwrites);
python ioctl struct layout hand-verified against
`struct fb_var_screeninfo` (40×u32 = 160 B) /
`struct fb_fix_screeninfo` (line_length at offset 52 on 64-bit).
Lua/shell gates unaffected (no code changed).
