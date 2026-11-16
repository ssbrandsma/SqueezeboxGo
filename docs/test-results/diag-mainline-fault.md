# Mainline boot-failure analysis — "dark display on boot attempt"

Branch: `diag/mainline-fault`. Author: diagnostics agent (Track A).
Base: main @ `ca32f0c` ([docs] Verified V4.0 hardware inventory).
Status: **analysis only — no boot-chain code changed in this round.**

Read first: [hardware inventory](../hardware.md), [project status](../project-status.md),
[bootloader DRAM verification](bootloader-dram-verification.md),
[HW test plan](HW_TEST_PLAN.md) §2/§5.

## 0. Verified facts this analysis takes as given (main @ ca32f0c)

- Unit: RG35XX H **V4.0** PCB, **H700** SoC, Samsung **LPDDR4** 8 Gb
  (K4F8E304HB-MGCJ), verified running **672 MHz, 32-bit, 1 rank, 1 GiB**.
  Our ddr4 SPL programs the same 672 MHz clock (`CONFIG_DRAM_CLK=672`,
  `CONFIG_SUNXI_DRAM_H616_LPDDR4=y`). V4.0 takes the **ddr4 image**.
- PMIC marked AXP717 / driven as AXP2202: stock runtime **DCDC2=940 mV**,
  **DCDC3=1100 mV**, both enabled — **exact match** with our SPL
  (`AXP_DCDC2_VOLT=940`, `AXP_DCDC3_VOLT=1100`), rails set **before**
  `sunxi_dram_init()` in `sunxi_board_init()`. Rail→net mapping still
  wants the stock boot0 PMU print; ALDO/BLDO/CLDO/CPUSLDO are kernel
  regulators in our DTS (compare-with-stock, don't assume).
- Stock chain: **Android-format boot image** on the stock GPT card
  (`root=/dev/mmcblk0p5`, `init=/init`, vendor 4.9.170, Ubuntu 22.04
  Jammy ARM64). Our chain: **SPL (sector 16) → FIT (`u-boot.itb`) →
  `boot.scr` → `Image` + `dtb.img`** on a SECOND card. Different cards,
  no conflict. **Never overwrite the working stock SD.**
- Display: stock shows `/dev/fb0` only (virt 1280x1024, LCD 640x480),
  no `/dev/dri`; ours drives panel via OOT DE2/TCON/PWM/nv3052c series
  (0.3.0+ only — **0.2.0-exp2 has NO panel driver**, so a dark display
  is *expected* even on a fully successful 0.2.0 boot).
- LEDs (both green, active-high; full table in `docs/hardware.md`):
  power = PI12/gpio 268 (on from SPL start), status = PI11/gpio 267
  (off → solid in `boot.scr` → kernel heartbeat → `led.sh` stages).
- UART: ttyS0, **115200 8N1**, header next to speaker + microSD slot;
  root shell over UART works on stock.

## 1. Ranked fault tree for "dark display on boot attempt"

Ranked by posterior probability given the verified facts above
(DRAM clock + PMIC rails matching demotes power/DRAM-parameter causes;
the 0.2.0-no-panel-driver fact dominates if the old image was booted).
Each hypothesis carries its **confirm** and **refute** signature —
one LED observation plus the exact UART line(s).

> Notation: `SPL>` = SPL banner block, `UB>` = U-Boot proper block,
> `K>` = kernel block. "Silent" = zero bytes at 115200 8N1 with TX/RX
> verified (see H8).

| Rank | Hypothesis | Confirm (LED + UART) | Refute (LED + UART) |
|---|---|---|---|
| H0 | **Test artifact: 0.2.0-exp2 booted fine, panel driver absent.** Applies only if the flashed image is 0.2.0-exp2 (no 0001-0005 OOT panel series). | Power **on**, status **off** (0.2.0 predates the status-LED scheme) + UART reaches login/`squeezeplay` with **no** `drm/panel` lines at all. | Image is 0.3.0-exp3 (check `MANIFEST.json` / filename / sha256) — then H0 is out and H1-H7 apply. |
| H1 | **SoC booted, panel/backlight chain dark.** OOT nv3052c/DE2/TCON init wrong, PWM backlight off/wrong pin, DT panel node mismatch, `Image`/`dtb.img` pair skewed. Most likely cause on 0.3.0: display is the only HW-gated driver left in the boot path. | Status reaches **heartbeat → timer stages → solid** (or strobe on service fail) + UART shows full kernel boot (`Starting kernel`, `Linux version 7.3.4`, systemd) **and** `dmesg` shows `drm/panel/backlight` errors, or no panel probe at all. | Any hang *before* `Starting kernel` (then H2-H5), or kernel panic (then H6). |
| H2 | **Wrong DRAM image on V4.0 (ddr3 flashed) or TPR mistune.** SPL trains the wrong type / mistuned PHY and hangs. Demoted but not eliminated: TPR/DX/ODT come from the upstream defconfig author, tuned for *an* LPDDR4 board, unconfirmed on V4.0. | Power **on**, status **off** + UART shows `U-Boot SPL 2026.10` banner then **hangs before** `DRAM: 1024 MiB`, or prints a DRAM error / `sunxi_dram_init` failure (SPL hangs loudly on 0 bytes, never silently mis-trains). | UART shows `DRAM: 1024 MiB` + `Trying to boot from MMC1` — DRAM trained, H2 out. |
| H3 | **SPL never ran (BROM found no card).** Bad flash, wrong slot, dead card, SPL blob clobbered (must sit at sector 16, end before LBA 4096), GPT damage. Note: stock Android-image boot from the same slot proves slot + BROM; a *second-card* failure points at our card/flash, not the board. | **Both LEDs dark** + **zero UART bytes** across power cycle (BROM itself is silent, so silence + dark = BROM never handed off). | Power LED **on**, or **any** `U-Boot SPL` byte — SPL ran, H3 out. |
| H4 | **SPL ran, U-Boot proper / FIT never loads.** SPL↔FIT blob mismatch (FIT staged as `u-boot.itb` from `u-boot.itb` or `u-boot-sunxi-with-spl.fit.itb`), corrupted second-card sectors, SPL built for the wrong boot device. | Power **on**, status **off** + `DRAM: 1024 MiB` and `Trying to boot from MMC1` present, then `SPL: failed to boot from all boot devices` (or FIT load error) and **no** `U-Boot 2026.10` banner. | `U-Boot 2026.10 ...` banner appears — H4 out. |
| H5 | **`boot.scr` / FAT load failure.** Missing/corrupt `boot.scr`, `Image`, or `dtb.img` on `mmc 0:1` (label SQUEEZEBOOT); `gpio set 267` failing (would need `CONFIG_CMD_GPIO` missing — verified present via `uboot-rg35xx-h-common-fragment.conf`); `booti` failing on a skewed Image/DTB pair. | Status LED tells the sub-stage: **still off** after `U-Boot` banner = `gpio set 267` never ran (script not found: `** Unable to read file boot.scr **`); **solid on** + `## Executing script at ...` then `** Unable to read file Image|dtb.img **` / `Wrong Image Format` / hang = payload load or `booti` failure. | UART shows `Starting kernel ...` — script + loads + `booti` all worked, H5 out. |
| H6 | **Kernel early hang / panic before framebuffer.** Wrong DTB (`sun50i-h700-anbernic-rg35xx-h.dtb` + OOT 0001-0006), console/earlycon mismatch hiding the log, regulator mismatch (ALDO/BLDO/CLDO/CPUSLDO are *compare-with-stock*, not verified), rootfs PARTUUID mismatch (`root=PARTUUID=0a1b2c3d-0002-...` vs flashed GPT). | Status **solid on, never heartbeat** + `Starting kernel ...` then silence (console/DT hang), or `Kernel panic`, or `VFS: Unable to mount root fs on ...` (PARTUUID/rootfs), or PMIC/regulator probe errors. | `Linux version 7.3.4` + subsequent driver lines + status **heartbeat** — kernel alive, H6 out. |
| H7 | **Userspace stall/failure with dark splash.** `firstboot` (dpkg configure / ssh-keygen) still running, `drm_splash` crashing on missing DRM device, `squeezeplay` failing, Wi-Fi stage hanging. Only reachable if kernel + heartbeat are seen. | Status blink names the stage: **fast 100 ms** = firstboot, **1 Hz** = splash, **slow 1000/250** = wifi, **strobe 50 ms** = a service FAILED (UART console / `journalctl -b` names it). Kernel log complete, no panic. | Status **solid on** + login prompt / UI on screen — boot complete, H7 out. |
| H8 | **Measurement artifact: UART wiring/baud wrong.** Looks exactly like H3 on the terminal (no bytes) but the board is fine. Always exclude before concluding H3. | **Power LED on** (SPL alive) with **zero UART bytes**; or garbage bytes (baud/parity wrong — must be **115200 8N1**); bytes appear after re-seating GND/RX/TX or swapping RX↔TX. | Clean `U-Boot SPL` text at 115200 8N1 — wiring fine, H8 out. |

Decision order on the bench: **H8 → H3 → H2 → H4 → H5 → H6 → H1/H7**
(exclude measurement, then walk the boot chain in time order; H0 is a
pre-check on the image version before anything else).

## 2. UART-log interpretation guide (expected banner sequence)

Capture at 115200 8N1 (see §3, probe P0). BROM prints nothing; the
first byte you see is the SPL banner. At each row, the LED column is
the state you must observe *at that point in the log*.

| Step | Expected UART text (anchors — version strings may vary) | LED state | Proves |
|---|---|---|---|
| 0. Power-on | *(silence — BROM loads SPL from SD sector 16)* | both off, then power **on** (`status_led_init` in SPL) | card readable, SPL entered |
| 1. SPL banner | `U-Boot SPL 2026.10 (Nov ...)` | power on, status off | SPL code running, UART TX alive |
| 2. DRAM train | `DRAM: 1024 MiB` | power on, status off | LPDDR4 trained at 672 MHz (H2 refuted) |
| 3. SPL→FIT handoff | `Trying to boot from MMC1` (then FIT load; ATF `NOTICE: BL31: v2.15.0 ...` may print) | power on, status off | SPL found the FIT image |
| 4. U-Boot proper | `U-Boot 2026.10 ...`, `CPU: ...`, `Model: Anbernic RG35XX H ...`, `DRAM:  1024 MiB`, `Core: ...`, `MMC: ...` | power on, status off → | U-Boot proper + its DTB alive (H4 refuted) |
| 5. boot.scr | `## Executing script at ...`, `gpio` OK (silent), `... bytes read in ... ms` for `Image` and `dtb.img`, optional `overlays/rg35xx-h-display.dtbo` applied or `** Unable to read file ... **` (non-fatal — `if load` guard) | status **solid on** (`gpio set 267`) | script ran, LED path works (partial H5 refute) |
| 6. Kernel entry | `Booting using the fdt blob at ...`, `Starting kernel ...` | status solid on | `booti` jumped (H5 refuted) |
| 7. Kernel boot | `Linux version 7.3.4 ...`, `Machine model: Anbernic RG35XX H`, `earlycon`, driver probes (`sunxi-mmc`, `axp20x`, `drm`, `panel`, `backlight`, `rtw_8821cs`), `Run /init as init process` / systemd banner | status **heartbeat** (`linux,default-trigger`, patch 0006) | kernel alive (H6 refuted) |
| 8. Userspace | systemd `[  OK  ] ...`, `firstboot` dpkg/ssh-keygen lines, splash, wifi, squeezeplay startup, login prompt | fast-blink → 1 Hz → slow-blink → **solid** (`led.sh`; strobe 50 ms = FAIL) | boot stage / completion (H7 scope) |

Quick triage from the *last* line of a hung log:

- Nothing at all → H3 vs H8 (check power LED).
- Ends inside step 1–2 → H2 (DRAM/variant).
- Ends at step 3 → H4 (FIT/SPL mismatch).
- Ends at step 4–5 → H5 (script/FAT/Image/DTB).
- Ends at step 6–7 (`Starting kernel`, no `Linux version`) → H6.
- Full log, dark screen → H1 (panel/backlight) — or H0 if 0.2.0.
- Full log + strobe → H7 (read the failing unit from UART/journal).

Reference: LED table in `docs/hardware.md` ("LEDs"); triage checklist
in `HW_TEST_PLAN.md` §5; `boot.cmd` source of step 5
(`platform/rg35xx-h/boot/boot.cmd`); `led.sh` signatures
(`platform/rg35xx-h/services/led.sh`).

## 3. Next probes — discriminate the top-3 hypotheses (user-run)

Pre-check (30 s, no UART): which image is on the card?

```sh
# On the build/flash host, not the device:
sha256sum -c SHA256SUMS              # in the release dir; all lines OK
# Record: filename (want 0.3.0-exp3 ddr4 on V4.0), sha256, Etcher/Rufus
# version, card brand/size, slot used. If the card holds 0.2.0-exp2,
# H0 already explains a dark display — reflash 0.3.0 ddr4 and re-test.
```

Top 3 after the H0 pre-check: **H1 (panel, SoC booted) vs H2 (DRAM
hang) vs H3 (SPL never ran)**. The probes below discriminate them in
one bench session. All commands are user-run (agent has no device
access). Nothing here writes the stock card.

**P0 — Instrumented power-on (discriminates H3/H2 from everything
downstream).**

```sh
# 1. Wire UART: GND/RX/TX to the 4-pin header (3.3 V TTL only), 115200 8N1.
# 2. Start capture BEFORE applying power:
picocom -b 115200 /dev/ttyUSB0 -l   # or: PuTTY serial + session logging
# 3. Insert the SECOND card (our image; stock card stays in its sleeve).
# 4. Power on in a dim room; watch BOTH LEDs; save the capture as
#    boot-<variant>-<date>.txt next to the results file.
```

Read: both dark + 0 bytes → H3/H8; power on + SPL banner → H3 out;
banner then hang before `DRAM: 1024 MiB` → H2; past DRAM → H2/H4/H5…

**P1 — If any U-Boot banner appears (kills H2/H3/H4; splits H5 from
H1/H6/H7).** Stop autoboot (press a key at the `Hit any key to stop
autoboot` countdown) and run at the `=>` prompt:

```
printenv bootcmd bootargs bootdelay
mmc info
fatls mmc 0:1
fatls mmc 0:1 overlays/
# Optional, only if a file looks short/corrupt:
size mmc 0:1 Image
size mmc 0:1 dtb.img
size mmc 0:1 boot.scr
boot            # continue the interrupted boot afterwards
```

Expected: `mmc info` shows the card, `fatls` lists `boot.scr`,
`Image`, `dtb.img` with sane sizes. Missing/short files → H5
(re-flash; record sha256). Clean listing + boot hangs later → H1/H6/H7.

**P2 — If the kernel boots but the screen stays dark (confirms H1 vs
H6/H7).** At the UART login prompt (root console):

```sh
uname -a; cat /etc/os-release; free -m
dmesg | grep -i -E 'drm|panel|tcon|de2|mixer|dsi|nv3052c|backlight|pwm|fb'
ls /sys/class/backlight/ 2>&1
cat /sys/class/backlight/*/brightness 2>&1
cat /sys/class/backlight/*/max_brightness 2>&1
ls /dev/fb0 /dev/dri 2>&1
dmesg | grep -i -E 'axp|regulator|mmc|rtw|8821' | head -40
cat /sys/class/leds/green:status/trigger 2>&1
journalctl -b --no-pager -p err | tail -30
```

Read: `drm/panel` probe errors or absent backlight entries → H1
(panel/DT/backlight — capture full `dmesg` for Agent 1). Panic or
`VFS: Unable to mount root fs` earlier → H6. Clean kernel + strobe /
stuck stage blink → H7 (the `journalctl` lines name the unit).

**P3 — If silence + dark (splits H3 card/flash from H8 wiring).**

1. Re-seat GND/RX/TX, confirm 3.3 V TTL header, swap RX↔TX once,
   re-try (H8 exclusion — garbage bytes = baud/parity, fix to 115200 8N1).
2. Re-flash the *second* card (Etcher validate-write on / Rufus DD
   mode), retry; try the other SD slot; try another card brand.
3. Sanity: boot the **stock card** and capture its known-good log
   (BROM/boot0 banner, DRAM print, PMU/rail lines, cmdline) — this
   proves slot + UART wiring in one shot and yields the stock PMU print
   the rail→net mapping still needs.
4. Only then: try the *other* DRAM variant once and record both
   attempts (V4.0 = ddr4 expected; a ddr3-booting V4.0 would overturn
   the verified DRAM fact — report verbatim).

Record every attempt (image sha256, slot, LED pair, last UART line) in
`docs/test-results/hw-<date>-<variant>.md` per `HW_TEST_PLAN.md` §4.
Redact secrets before committing.

## 4. Proposed next instrumentations (NOT implemented — approval-gated)

Only if §3 shows an *early* hang (no `Starting kernel`). Each is the
minimal change that buys the missing signal; none touch the stock-card
story (all on the second card, all reversible by reflash).

1. **SPL DRAM debug print (if hang at step 1–2 / H2 suspected).**
   One-gate build: enable SPL serial DRAM debug in the ddr4 U-Boot
   build only (`CONFIG_SPL_SERIAL` + sunxi DRAM debug prints / TPR
   dump at the `mctl_phy_*` training call sites in
   `dram_sun50i_h616.c`), print `dram_para` (clk/type/TPR/ODT) before
   training and the trained size after. Signal: exact training step
   that hangs → TPR vs clock vs type verdict. Cost: one U-Boot-only
   rebuild, no kernel/rootfs churn.
2. **U-Boot `bootdelay` + `boot.scr` echo markers (if hang at step
   3–5 / H4-H5 suspected).** Set `bootdelay=5` (interruptible prompt
   without racing autoboot) and add `echo` markers around each
   `boot.scr` line (`echo "SB: gpio ok"`, `echo "SB: Image loaded"`,
   …). Signal: last marker = exact failing load. Cost: `boot.cmd` +
   fragment edit, `mkimage` rebuild of `boot.scr` only — no SPL/kernel
   rebuild.
3. **Kernel early-visibility bootargs (if hang at step 6–7 / H6
   suspected).** Ship a debug `boot.scr` variant appending
   `loglevel=8 initcall_debug earlycon keep_bootcon` (keep
   `console=ttyS0,115200n8`). Signal: last initcall / driver probe
   before silence → DT vs regulator vs MMC/rootfs verdict. Cost:
   `boot.cmd` one-line variant, reversible by swapping `boot.scr`.
4. **SPL alive-blink (last resort, only if power-LED evidence is
   ambiguous).** Toggle PI12 in the SPL DRAM-retry loop so "SPL hung
   in training" (blinking) differs from "BROM never ran SPL" (dark).
   Signal: disambiguates H2 vs H3 without UART. Cost: small SPL patch;
   keep out of the default build (timing-sensitive training path).

Suggested order: 2 → 3 → 1 → 4 (cheapest, most-likely-first). Each
proposal needs its UART log from §3 attached before implementation.

## 5. Files referenced (read-only in this round)

- `platform/rg35xx-h/boot/boot.cmd` — SPL→FIT→boot.scr chain, `gpio
  set 267`, `root=PARTUUID=0a1b2c3d-0002-...`, `Image`+`dtb.img` loads.
- `platform/rg35xx-h/kernel/build-uboot.sh` + `config/uboot-rg35xx-h-*`
  — ddr4 = defconfig as-is, ddr3 = fragment swap, `CONFIG_CMD_GPIO=y`.
- `platform/rg35xx-h/kernel/pins.env` — U-Boot v2026.10 `55084065`,
  ATF v2.15.0, Linux v7.3.4.
- `platform/rg35xx-h/device-tree/rg35xx-h-leds-oot.dtsi` (+ patch
  0006) — kernel heartbeat trigger.
- `platform/rg35xx-h/services/led.sh` — userspace stage signatures.
- `build/image/assemble-image.sh` (read-only peek) — SPL at sector 16,
  FAT `SQUEEZEBOOT` at sector 32768, PARTUUID layout.
