# Stock inventory + PoC readiness (hardware agent) — test results

Date: 2026-11-16 12:25 UTC. Branch: `hw/stock-poc`.
Device: RG35XX H V4.0 (H700), stock Ubuntu 22.04 / kernel 4.9.170,
via `ssh rg35xxh` as user `muse` (key auth, no sudo).
Note: device clock read April 2022 at session start; NTP synced it to
correct UTC mid-inventory (~12:19 UTC). Pre-sync file mtimes unreliable.

## Summary

| Check | Status | Notes |
|---|---|---|
| DT walk + tarball | PASS | 6074 files, model sun50iw9, panel fog_fj035fhd05_v1 |
| System inventory | PASS | ps/units/lsmod/net/mount/libs captured |
| Frontend map | PASS | launcher.service -> loadapp.sh respawn loop -> dmenu.bin (SDL1.2 fbcon, armhf) |
| Audio + owner | PASS | dmenu thread holds hw:audiocodec (XRUN); asound.conf captured |
| Graphics | PASS | fb0 1280x1024x16 live; stale 640x480x32 dump decoded; no DRI/backlight |
| Input | PASS | 3 devices, DT key codes decoded, no by-id (use by-path) |
| Sleep | PASS | vendor-driven mem suspend; systemd targets masked; cycle in dmesg |
| Regulators/PMIC | PASS | AXP2202 @0x34, all rails match docs/hardware |
| Native build+run ($HOME) | PASS | gcc hello + openprobe run as muse |
| fb/snd/input open as muse | FAIL | EACCES x5 (expected privilege wall, recorded) |
| sudo as muse | FAIL | setuid bit missing (expected, fix below) |
| stock-probe.sh unprivileged | PASS | ran, tarball verified; 1 quoting bug filed below |
| Jammy payload staging | PASS | tarball sha OK on device, extract + full ldd clean |
| jive launch on stock | BLOCKED | needs fb+input+audio access (sudo fix) |
| Sysroot feasibility | PASS | 5/5 debs fetch+sha+extract, libc 2.35 + asound verified |

Totals — PASS: 13, FAIL: 2 (both are the documented privilege wall),
NOT RUN: 0, BLOCKED: 1.

## Details

### DT walk — PASS

`/proc/device-tree` readable; `/sys/firmware/fdt` EACCES. Direct
`tar -C /proc` yields 137 bytes (procfs), so: `cp -r` to `$HOME`
(6074 files, 24 MB) -> tarball -> scp. Full decode in
`docs/hw-evidence/stock-dt-notes.md`. Highlights: LPDDR4 @672 MHz
(type 8, clk 0x2a0), TPR/MR block, AXP2202 @0x34, LCD
640x480/ht770/vt528/dclk24/pwm0-50kHz, panel `fog_fj035fhd05_v1`,
gpio-keys poll 20 ms with all 19 key codes, OPP 480-1512 MHz.

```text
model: sun50iw9 | compatible: allwinner,h616 + arm,sun50iw9p1
memory: 1 GiB @ 0x40000000
```

### System — PASS

Hostname ANBERNIC, Ubuntu 22.04 Jammy, glibc 2.35, kernel 4.9.170
(build May 2026, Linaro gcc 5.3). PID 1 = `/init` (vendor init, not
systemd as PID 1; systemd userland still runs services). 973 MB RAM,
no swap. Modules: only mali_kbase, 8821cs, rtl_btlpm (rest built in).
Failed units: upower.service, systemd-binfmt.service. wlan0
192.168.1.117 UP; wlan1 AP iface down; 2nd SD mmcblk1 117 GB
(108 GB used) at /mnt/sdcard. Partitions match docs/hardware map.

SDL/library landscape (all in `system-libs.txt`, `frontend-sdl*.txt`):
dmenu = 32-bit armhf, SDL1.2 fbcon (vendor SDL1.2 has ONLY fbcon +
dummy drivers). Vendor SDL2 2.0.12 in /lib (MALI EGL + dummy video,
ALSA audio). Ubuntu SDL2 dir holds TWO hand-built libs (neither
dpkg-owned): 2.0.18-era + 2.28.5 (0.2800.5, effective). Vendor
EGL/GLES 4 KB shims -> 19 MB libmali.so.0.20.0. libasound 1.2.6.1
arm64+armhf, -dev packages installed. Full native toolchain on device
(gcc/make/pkg-config/sdl2-config/evtest 1.33/qemu-aarch64/ffmpeg).

### Frontend — PASS

`launcher.service` (sysv-generated, Restart=no) -> `launcher.sh start`
(backgrounds) -> `loadapp.sh` -> infinite `while [ -f dmenu_ln ]`
respawn loop (NO delay; crash path sleeps 30 s) -> `dmenu_ln` ->
`/mnt/vendor/bin/dmenu.bin` (armhf, SDL1.2+image+ttf+gfx, ~48% CPU
busy-loop). Stop hooks: /tmp/stopAPP.ini (checked between runs only),
`killall -s SIGUSR1 dmenu.bin` (stop path, needs root). No
brightCtrl.bin, no muos/vp overrides, no appfs.img. Community mod
`/mnt/mod/ctrl/autostart` (G.R.H.) runs at boot as root.

### Audio — PASS

Cards 0 audiocodec / 1 ahubdam (no PCMs) / 2 ahubhdmi.
`/etc/asound.conf`: default -> hooks -> hw:audiocodec (LINEOUT+SPK+
DAC paths on, digital vol 63); playback_hp/hdmi likewise.
Owner: **dmenu.bin audio thread (TID 2461)** holds pcmC0D0p,
state XRUN, subdevices_avail 0 (found via /proc/asound; fuser is
blind here — non-root cannot read root's /proc/PID/fd).
`aplay -l` / `amixer` as muse fail (not in audio group) — see wall.

### Graphics — PASS

/proc/fb `0` (empty name); no fbset; no /dev/dri; no backlight class;
disp attr nodes EACCES. Live sysfs: virtual 1280x1024, 16 bpp,
stride 2560, modes 1280x1024p-59 + 640x480p-59. Stale first-boot
fb_var dump (mod's fb.cfg) decodes to 640x480x32 XRGB, virt 640x960
(double-buffer, yoffset 480), 24 MHz pixclock, 150x94 mm — matches DT
timings exactly. DISCREPANCY (honest): live sysfs (1280x1024x16)
vs first-boot dump (640x480x32) — resolve post-sudo with live
FBIOGET_VSCREENINFO. /dev/mali0 is world-RW (openable, verified).

### Input — PASS

event0 axp2202-pek, event1 ANBERNIC-keys (+js0), event2
dierct-keys-polled (vendor typo). NO /dev/input/by-id — discover via
by-path or NAME. event* root:input (denied); js0 world-readable
(openable, verified). DT key codes decoded (see DT notes).

### Sleep — PASS

systemd sleep/suspend/hibernate targets masked-runtime; suspend is
100% vendor-driven: dmenu idle timer ("++++ timer to sleep" strings)
-> `pwr_new.sh` -> `echo -n mem > /sys/power/state`.
/sys/power/state = `freeze mem`; wakelocks present; dmesg shows a
full suspend (7.1 s) + resume cycle with the known harmless
`hci: ERR: hcd is null` noise. upower failed. logind
HandlePowerKey=ignore. ~85 s idle sleep rule CONFIRMED mechanism.

### Privilege wall — FAIL (expected, evidence)

```text
/dev/fb0: FAIL errno=13 (Permission denied)
/dev/snd/pcmC0D0p: FAIL errno=13 (Permission denied)
/dev/snd/controlC0: FAIL errno=13 (Permission denied)
/dev/input/event1: FAIL errno=13 (Permission denied)
/dev/input/js0: OPEN-OK fd=3
/dev/mali0: OPEN-OK fd=3
/sys/firmware/fdt: FAIL errno=13 (Permission denied)
/sys/class/disp/disp/attr/sys: FAIL errno=13 (Permission denied)
$ sudo -n true
sudo: /usr/bin/sudo must be owned by uid 0 and have the setuid bit set
$ ls -la /usr/bin/sudo
-rwxr-xr-x 1 root root 215944 Feb 14 11:48 /usr/bin/sudo
$ groups
muse sudo
```

Native $HOME build+run works (hello + openprobe, both aarch64 PIE).

### stock-probe.sh — PASS (with 1 bug to fix)

Ran unprivileged on device; tarball
`stock-probe-20261116T121941Z-ANBERNIC.tar.gz` (52 KB) verified
`sha256sum -c ... OK`; committed under docs/hw-evidence/.
BUG for probe owner: section 90 "frontend-like processes" fails with
`sh: 1: Syntax error: Unterminated quoted string` [exit=2] — the
`grep -i -E '[e]mulat|...` single-quoted pattern collides with the
wrapping `sh -c '...'`. Data covered manually in this report.

### Jammy payload staging — PASS

Tarball 673ec5ee... (23.5 MB, 3103 files) scp'd to
~/squeezebox-dev/, sha re-verified ON device, extracted to
~/squeezebox-dev/sp-stage (NOT /opt — unprivileged).
`bin/jive`: aarch64 PIE, max GLIBC_2.34, zero __isoc23 (independently
reconfirmed on device). `ldd` with bundle lib/: zero "not found";
jive_alsa resolves stock libasound. Launch NOT attempted (blocked).

Device footprint (all under $HOME, ~92 MB): ~/squeezebox-dev (68 MB:
hello/openprobe sources+bins, stock-probe.sh + tarball, jammy tgz +
sp-stage), ~/dt-copy (24 MB, deletable), ~/dt-copy.tar.gz (124 KB).

## HANDOFF — the ONE command + what it unblocks

### (a) Owner: run this on the UART root shell

```sh
chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo
```

Optional (same shell, recommended so the video/audio/input PoC can
run as `muse` without sudo for every test):

```sh
usermod -aG video,audio,input muse
```

Verify: `ssh rg35xxh 'sudo -n true && echo SUDO_OK; groups muse'`.

### (b) What unblocks the moment sudo works

1. `sudo fuser -v /dev/snd/*` — true ALSA holder list (expected:
   dmenu thread; stop frontend before exclusive hw: open).
2. Framebuffer PoC: live FBIOGET_VSCREENINFO (resolve the
   1280x1024x16-vs-640x480x32 question), fbcon test pattern,
   then SDL1.2-fbcon jive (compat SDL needs /dev/dri, so stock
   video = SDL1.2-fbcon route per ui/stock-fbcon-BUILD.md).
3. evtest on event1/event2 (verify DT key codes incl. L2/R2=314/315,
   hat dpad 16/17) to finalize evdev2jive.map.
4. Frozen mixer snapshot: `sudo amixer contents` per card (muse
   cannot open controlC0 today).
5. Suspend control: unmask/inspect sleep path, measure idle timer,
   test wake sources for the appliance power story.
6. Launch staged jive: `LD_LIBRARY_PATH=.../lib SDL_VIDEODRIVER=fbcon
   bin/jive` (after stopping dmenu via the stop path — needs root).

## Cross-agent notes

- Platform: stock panel ID `fog_fj035fhd05_v1` — confirm OOT init
  sequence targets this module; full TPR/MR block in DT notes.
- UI: 19 DT key codes decoded (hat dpad, L2/R2=314/315); no by-id.
- Audio: dmenu holds pcmC0D0p in XRUN — stop unit first, never force;
  fuser is blind unprivileged, use /proc/asound + owner_pid.
- Core: staged jive is link-clean; needs GLIBC<=2.34 only. Good.
- QA: probe quoting bug (section 90) needs a fix in stock-probe.sh.

## Reproduce

```sh
git checkout hw/stock-poc
ls docs/hw-evidence/   # 31 files incl. DT tarball, config.gz, probe tarball
```
