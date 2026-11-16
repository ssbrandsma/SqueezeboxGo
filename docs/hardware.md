# Hardware (RG35XX H, H700)

Status levels: **identified** (seen on board / datasheet), **in-DTS**
(present in mainline device tree), **HW-gated** (needs device probe).
Distinguish SoC capability vs driver vs firmware vs hardware-verified
in all claims.

## Identified unit (user report 2026-11-16, PCB markings)

- PCB revision: **RG35XX H V4.0**, date `2024-01-08`.
- SoC: **Allwinner H700** (H616 class; U-Boot `MACH_SUN50I_H616` + ATF BL31).
- PMIC: **AXP717** (matches U-Boot `CONFIG_AXP717_POWER` + kernel AXP717 nodes).
- DRAM: Samsung `SEC 306 / K4F8E30 / 4HBMGCJ` → part
  **K4F8E304HB-MGCJ**: **8 Gb LPDDR4 SDRAM** (not DDR3, not desktop DDR4,
  not LPDDR4X), 256M x 32, 200FBGA, **1.1 V**, rated to 3200–3733 MT/s
  (Samsung datasheet Rev 1.0 + distributor specs corroborated 2026-11-16).
  Single die = **1024 MiB** total, matching the `~1 GB` assumption.
- Our firmware runs this die at **672 MHz clock (1344 MT/s)** per the
  pinned U-Boot defconfig — conservative vs the 3200+ rating.

Consequence: V4.0 units take the **ddr4 (LPDDR4) image**. The `ddr3`
variant is retained for other board revisions *if they exist* — no DDR3
unit has been sighted; its TPR tuning is unvalidated (see
[bootloader DRAM verification](test-results/bootloader-dram-verification.md)).

## Board (in-DTS + prior survey)

- 3.5" IPS 640x480 4:3, no touch. Panel: `fog_fj035fhd05_v1`-class 640x480
  RGB, PWM ch0 backlight (muOS sunxi.dts timing reference; mainline DTS
  has no panel nodes — display is our OOT package).
- Controls: D-pad, ABXY, Start/Select, L1/R1/L2/R2, 2 clickable sticks
  (mainline: 4ch adc-joystick via gpio-mux+gpadc + gpio-keys).
- Audio: internal sun4i-codec LINEOUT + hp-detect; speakers + 3.5 mm jack.
- Net: RTL8821CS SDIO Wi-Fi (mmc1, PG15-19 pwrseq) + BT (uart1).
  Driver: RTW88_8821CS; firmware: `firmware-realtek` in image.
- Power: AXP717 (battery/ADC); USB-C charging + OTG/host; 2nd USB;
  dual microSD.
- GPU: Mali-G31 (Panfrost kernel driver on; Mesa userspace deferred).

## UART debug (user-reported, pinout TBD)

- Four-pin UART debug connector next to the speaker and microSD slot.
- Pinout and voltage level NOT yet identified — verify (continuity to
  SoC UART TX/RX/GND, 3.3 V TTL expected) before connecting; never feed
  5 V or RS-232 levels. Reference (unverified for V4.0):
  steward-fu.github.io RG35XX H UART page.
- Plan: capture a **known-good boot log on stock firmware first**, then
  the same capture on our image. Checklist: boot0/BROM banner, DRAM
  size + type print, PMU/rail lines, partition/boot-device lines, kernel
  version + cmdline, login prompt. Diffs isolate our bugs from board facts.
