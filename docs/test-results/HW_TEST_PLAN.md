# HW test plan — first experimental image (WP2)

Human-run procedure for the first `.img` on a physical RG35XX H.
Record results in a dated copy of the matrix below
(`docs/test-results/hw-<date>-<variant>.md`). Statuses:
**PASS** / **FAIL** / **NOT RUN**, same meanings as the host gates.

Preconditions:

- Image validated by the host gate:
  `python3 tests/check_image.py /path/to/squeezebox-rg35xx-h-<variant>.img`
  must print `PASS` (GPT layout, SPL, boot files, DTB, no-secrets, size).
- Know your unit's DRAM variant (DDR3 vs DDR4); flash the matching
  image. Unit DRAM-ID method: TBD on hardware — if unsure, try DDR4
  first, then DDR3, and record which booted.
- microSD card >= 4 GB, USB-C cable, 3.5 mm headphones (for audio).

Safety:

- Flashing writes a whole disk. Triple-check the target drive letter /
  device in Etcher/Rufus; never flash the host OS drive.
- UART: verify header pinout and voltage (3.3 V TTL assumed — confirm at
  the steward-fu RG35XX H UART reference) before connecting. Never feed
  5 V or RS-232 levels into the header.

## 1. Flash

1. Download the release dir (`*.img.xz` + `SHA256SUMS` + `MANIFEST.json`).
2. Verify: `sha256sum -c SHA256SUMS` (Linux) or
   `bash releases/checksum.sh verify <dir>` — all lines `OK`.
3. Decompress (`xz -d -k *.img.xz`) and flash with
   [balenaEtcher](https://etcher.balena.io/) (Validate write: on) or
   [Rufus](https://rufus.ie/) (DD mode, not ISO mode).
4. Eject safely, insert the card into the RG35XX H (lower slot if two).

Record: tool + version, image filename, sha256, card size/brand.

## 2. Boot log via UART

1. Connect USB-UART (GND/RX/TX, 115200 8N1) to the debug header.
2. Open a terminal capture (`picocom -b 115200 /dev/ttyUSB0 -l`,
   or PuTTY serial + session logging to file).
3. Power on. Expected sequence: Allwinner BROM → SPL banner →
   U-Boot (`U-Boot 2026.10 ... DRAM: 1024 MiB`) → `boot.scr` →
   kernel (`Linux version ...`) → init splash → SqueezePlay UI.
4. Save the full log as `boot-<variant>-<date>.txt` next to the results.

FAIL if: no SPL output (wrong DRAM variant or dead SPL sector),
U-Boot loops, kernel panic, or no login/UI within 90 s.

## 3. Boot log via SSH

1. After UI is up, find the unit's IP (UI network screen, or router DHCP).
2. `ssh root@<ip>` (default creds per release notes; change on first login
   if the image ships a default password — record that you did).
3. Capture: `uname -a; dmesg | head -50; journalctl -b --no-pager | tail -30;
   cat /etc/os-release; free -m`.

## 4. Test matrix

Copy this table into the results file and fill Status + Notes.

| # | Area | Steps | Expect | Status | Notes |
|---|---|---|---|---|---|
| H1 | Boot (cold) | Power off 10 s, power on, time to UI | UI visible <= 90 s, no panic in UART log | NOT RUN | |
| H2 | Boot (reboot) | `reboot` over SSH, time to UI | Same as H1 | NOT RUN | |
| H3 | Display | Splash at boot, UI fills 640x480, no tearing | Full-screen 640x480, readable text | NOT RUN | |
| H4 | Backlight | UI brightness up/down (or `/sys/class/backlight`) | Visible steps, no flicker | NOT RUN | |
| H5 | D-pad + ABXY | Navigate menus, select/back | Matches `ui/input/rg35xxh.map` | NOT RUN | |
| H6 | Start/Select/L1/R1 | Play/pause, home, prev/next | Actions fire once per press, clean release | NOT RUN | |
| H7 | L2/R2 volume | Hold VolDown/VolUp | Smooth volume change, repeat works | NOT RUN | |
| H8 | Sticks | Move sticks, click | Scroll (if mapped), no drift at rest | NOT RUN | |
| H9 | Speaker audio | Play stream/track | Clear stereo, no underruns (`dmesg` clean) | NOT RUN | |
| H10 | Headphone jack | Plug 3.5 mm during playback | Auto-switch to HP, speakers mute | NOT RUN | |
| H11 | Volume/mute | UI volume 0/50/100 + mute | Consistent, no stale Now Playing | NOT RUN | |
| H12 | Wi-Fi connect | Join 2.4 GHz AP, `ping -c3 <gateway>` | Associated, < 5 % loss | NOT RUN | |
| H13 | Wi-Fi stream | Play radio/stream 5 min | No dropouts, UI responsive | NOT RUN | |
| H14 | Battery % | Compare UI % vs `cat /sys/class/power_supply/*/capacity` | Agree within 5 % | NOT RUN | |
| H15 | Charging | Plug USB-C, check icon + `.../status` | `Charging`, % rises | NOT RUN | |
| H16 | Standby/wake | Short-press power, then wake | Sleeps, wakes to UI < 5 s | NOT RUN | |
| H17 | Shutdown | Long-press power / UI power off | Clean poweroff, no fs errors next boot | NOT RUN | |
| H18 | Now Playing | Play from available source | Title/artist/state correct, updates on switch | NOT RUN | |

Hardware evidence checklist (attach to results file):

- [ ] UART boot log (`boot-<variant>-<date>.txt`)
- [ ] SSH capture (`ssh-<variant>-<date>.txt`: uname/dmesg/journal/os-release)
- [ ] Photo of UI on device (optional but recommended)
- [ ] `aplay -l` + `evtest` (one key each) pastes, if run

## 5. Failure triage

- No UART output at all → re-flash, try other DRAM variant, try another
  SD card; record all three attempts.
- SPL ok, U-Boot missing → SPL/U-Boot blob mismatch; capture log, file
  against Agent 1 with the exact image sha256.
- Kernel boots, no display → panel/DTB issue; SSH in, capture
  `dmesg | grep -i -E 'drm|panel|fb|display'`.
- Kernel boots, no audio → capture `aplay -l; dmesg | grep -i audio`;
  file against Agent 3.
- Wi-Fi missing → capture `dmesg | grep -i -E 'rtw|8821|mmc1|brcm'`;
  file against Agent 1.

Never paste secrets (passwords, tokens, AP keys) into results files —
redact before committing.
