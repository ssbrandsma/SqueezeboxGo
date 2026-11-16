# Hardware (RG35XX H, H700)

Status levels: **verified** (observed on device via UART root shell),
**identified** (seen on board / datasheet), **in-DTS** (mainline device
tree), **HW-gated** (still needs a probe). Distinguish SoC capability vs
driver vs firmware vs hardware-verified in all claims.

## Identified unit (PCB markings + verified boot)

- PCB revision: **RG35XX H V4.0**, date `2024-01-08`.
- SoC: **Allwinner H700** (H616 class), 4x Cortex-A53, AArch64 — verified
  via booted OS.
- DRAM: Samsung `SEC 306 / K4F8E30 / 4HBMGCJ` → **K4F8E304HB-MGCJ**: 8 Gb
  **LPDDR4** SDRAM, 256M x 32, 1.1 V, rated 3200–3733 MT/s. **Verified
  running at 672 MHz, 32-bit, single rank, 1 GiB** (stock boot).
  Our SPL programs the same 672 MHz clock.
- PMIC: chip marked **AXP717**; vendor bootloader/drivers identify it as
  **AXP2202** (naming alias — same silicon generation). I2C bus 5,
  address 0x34. Battery healthy: 84%, 3.99 V at inventory time.
- Consequence: V4.0 takes the **ddr4 (LPDDR4) image**. No DDR3 unit sighted.

## Verified stock environment (root shell over UART)

- OS: **Ubuntu 22.04 LTS Jammy ARM64** (!). Kernel: vendor **4.9.170**.
  **glibc 2.35** — our 24.04-built ARM64 binaries (need 2.38) will NOT run
  as-is; stock PoC needs a Jammy-compatible rebuild (in progress).
- Stock userspace ships **SDL2**, **Mali GPU libraries**, framebuffer
  graphics, and an **active OpenSSH server** (video backend TBD).
- UART: ttyS0, 115200 8N1. Four-pin header next to speaker + microSD slot.
  SSH access being established by owner (pending IP/credentials).
- DT model `sun50iw9`, compatible `allwinner,h616` + `arm,sun50iw9p1`
  (BSP sun50iw9 = mainline H616/H700 class).
- Wi-Fi module `8821cs` (vendor out-of-tree; ours: in-tree RTW88_8821CS).
- GPU module `mali_kbase`; BT module `rtl_btlpm`.
- Storage: stock GPT, first partition at sector 73728 (36 MiB):
  1. Roms 2 GiB VFAT; 2. boot-resource 32 MiB VFAT; 3. env 16 MiB;
  4. boot 64 MiB; 5. rootfs 7 GiB ext4 (`root=/dev/mmcblk0p5`, `init=/init`);
  6. appfs 4 GiB ext4 @ /mnt/vendor; 7. UDISK ~1.3 GiB ext4 @ /mnt/data.
- Stock bootloader uses an **Android-format boot image** (separate chain
  from our SPL→FIT→boot.scr; no conflict — different SD cards).
- **Never overwrite the working stock SD.** All our images go on a
  SECOND card until explicitly authorized otherwise.

## Verified audio (ALSA)

- Cards: 0 `audiocodec`, 1 `ahubdam`, 2 `ahubhdmi`.
- Playback: `hw:CARD=audiocodec,DEV=0`, `plughw:...`, `hw:CARD=ahubhdmi`,
  `playback_hp`, `playback_hdmi`, `bluealsa`.
- Mixers: LINEOUT, OutputL/R Mixer DACL/DACR, SPK, digital volume,
  lineout volume, tx hub mode.
- Speaker amp: **SGM4865** (verified marking).
- **The internal PCM was occupied during inventory — identify the audio
  owner (`fuser -v /dev/snd/*`) before any exclusive playback attempt.**

## Verified graphics (stock kernel)

- `/dev/fb0` exists; `/dev/dri` does NOT. Framebuffer virtual_size
  1280x1024 vs physical LCD 640x480 (scaling/orientation TBD — probe
  `fbset`, vinfo stride/pixelformat before assuming).
- Mali via `mali_kbase` kernel module; vendor stack is legacy fb.
- Stock DT (`lcd_driver_name`) and U-Boot log confirm panel
  **`fog_fj035fhd05_v1`** 640x480 (our OOT nv3052c binding must be
  confirmed against this exact panel on HW).
- Vendor SDL2 2.0.12 = MALI-EGL + dummy video only; Ubuntu SDL2 dir holds
  two hand-built 2.28.5 libs (not dpkg-owned). dmenu.bin itself is 32-bit
  armhf using **SDL1.2-fbcon**. Stock PoC video = SDL1.2-fbcon build.
- **Our SDL2/KMSDRM stack cannot be assumed to work on the 4.9 kernel.**

## Verified input (discover by NAME, never hardcode eventN)

- event0 `axp2202-pek` (power button), event1 `ANBERNIC-keys` (GPIO keys,
  joystick, analog), event2 `dierct-keys-polled` (sic — vendor typo).
- Numbers can shift: match by-path (no by-id on stock), then read
  actual evdev codes before finalizing any map. `dierct-keys-polled`
  is the stock map partner to ANBERNIC-keys; PEK stays hands-off.
- Frontend `dmenu.bin` holds ALSA (owner TID observed); it respawns via
  `loadapp.sh` infinite loop under `launcher.service` — stop the SERVICE
  (reversible), never kill the binary alone.

## Verified PMIC runtime (read-only; do NOT retune without evidence)

| Rail | Stock runtime | Our SPL setup | Note |
|---|---|---|---|
| DCDC1 | 1160 mV en | — (not touched) | leave alone |
| DCDC2 | 940 mV en | `AXP_DCDC2_VOLT=940` | **exact match** |
| DCDC3 | 1100 mV en | `AXP_DCDC3_VOLT=1100` | **exact match, LPDDR4 VDD2/VDDQ** |
| DCDC4 | 1000 mV dis | — | leave alone |
| ALDO1/3/4, BLDO2 | 1800 mV en | kernel regulators (mainline DTS) | compare, don't assume |
| CLDO1/3/4 | 3300 mV en | kernel regulators (mainline DTS) | compare, don't assume |
| CPUSLDO | 900 mV en | kernel (mainline DTS) | compare, don't assume |

Runtime voltages ≠ boot sequencing requirements. Our SPL order (rails
before DRAM training) is verified in source; rail→net mapping still
wants the stock boot0 PMU print.

## LEDs (boot progress, both green, active-high)

- **Power** (PI12, U-Boot gpio 268): ON from SPL start
  (`status_led_init`), stays on via kernel `default-state = "on"`.
- **Status** (PI11, U-Boot gpio 267): off until U-Boot proper, then:

| Status LED | Power LED | Meaning (0.3.0+) |
|---|---|---|
| off | off | BROM never ran SPL: power, SD slot/flash, or dead card |
| off | on | SPL alive (or hung in DRAM init); U-Boot proper not reached |
| solid on | on | U-Boot proper running `boot.scr`, kernel not started |
| heartbeat | on | kernel alive, userspace not started yet |
| fast blink 100 ms | on | `firstboot` (dpkg configure / ssh-keygen) running |
| 1 Hz blink | on | splash stage |
| slow blink 1000/250 | on | Wi-Fi stage |
| solid on | on | squeezeplay running = boot complete |
| strobe 50 ms | on | a service FAILED (see UART/journal for which) |

Implementation: SPL (defconfig) → `boot.cmd` (`gpio set 267`, needs
`CONFIG_CMD_GPIO` from `uboot-rg35xx-h-common-fragment.conf`) → DT
`linux,default-trigger = "heartbeat"` (patch 0006) → `services/led.sh`
stages (`trigger=timer`, needs `CONFIG_LEDS_TRIGGER_TIMER=y`). Kernel
names: `green:power`, `green:status` under `/sys/class/leds`.
Note: 0.2.0-exp2 predates this scheme (power LED only, no heartbeat —
an 0.2.0 unit that boots fully shows power on + status off).

## UART plan (access WORKS)

Known-good stock boot log first (BROM/boot0 banner, DRAM print, PMU
lines, partitions, kernel version/cmdline), then the same capture on our
image; diff them. Save logs next to results (`boot-<variant>-<date>.txt`).

## SSH access + sleep behavior (verified 2026-11-16)

- SSH `rg35xxh` (muse, key auth) works. **sudo/su/pkexec lost setuid —
  no privilege path from SSH** until the owner runs on the UART root
  shell: `chown root:root /usr/bin/sudo && chmod 4755 /usr/bin/sudo`
  (+ optional `usermod -aG video,audio,input muse`). Rootfs is NOT
  nosuid; only fusermount3 retains setuid. No escalation attempts.
- Stock suspends after ~80–85 s idle (`hci: ERR: hcd is null`, comms
  silent until wake — verified, not a wiring fault). SSH keepalive does
  NOT prevent it. Mechanism: vendor-driven (dmenu idle timer →
  `pwr_new.sh` → mem); systemd targets already runtime-masked. Clean
  suspend/resume observed (7.1 s) — stopping dmenu likely also stops
  auto-suspend (to verify). Keep device commands short; treat timeouts
  as SLEEP (retry once, then BLOCKED-on-wake), never as crash/failure.
