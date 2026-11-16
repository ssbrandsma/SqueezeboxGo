# Stock device-tree notes (RG35XX H V4.0, vendor kernel 4.9.170)

Source: `rg35xxh-stock-devicetree.tar.gz` — 6074 files copied from live
`/proc/device-tree` (SSH user `muse`, 2026-11-16; `/sys/firmware/fdt`
itself is EACCES for non-root so the raw blob could not be taken).
All multi-byte integers below decoded big-endian (DT native order).

## Root identity

- `model` = `sun50iw9`
- `compatible` = `allwinner,h616`, `arm,sun50iw9p1`
- `memory@40000000`: reg base `0x40000000` size `0x40000000` = **1 GiB**
- `chosen/bootargs` == live `/proc/cmdline` (verified identical),
  incl. `androidboot.hardware=sun50iw9p1`, `cma=64M`,
  `disp_reserve=1228800,0x7bf23800`, `lcd_type=old`, `init=/init`.

## CPUs

- 4x `arm,cortex-a53` (`cpu@0..3`, MPIDR 0x0/0x100/0x200/0x300),
  `operating-points-v2` -> `opp_l_table` (shared).
- OPP bins: 480 / 600 / 720 / 792 / 936 / 1008 / 1032 / 1104 /
  1200 / 1296 / 1320 / 1344 / 1416 / 1512 MHz (per-bin voltage
  variants `-0..-3`, `-ab`).
- Thermal zones: `cpu_thermal_zone`, `ddr_thermal_zone`,
  `gpu_thermal_zone`, `ve_thermal_zone`.
- `pmu` node here = `arm,armv8-pmuv3` (perf), NOT the PMIC.

## DRAM (LPDDR4, matches V4.0 board)

`dram` node (`allwinner,dram`), all values BE hex:

| Param | Value | Param | Value |
|---|---|---|---|
| dram_type | 0x8 = LPDDR4 | dram_clk | 0x2a0 = **672 MHz** |
| dram_zq | 0x08080808 | dram_odt_en | 0x0e0e0e0e |
| dram_para1 | 0x00000e0e | dram_para2 | 0x7887bbbb |
| dram_ca_dri | 0x00000e0e | dram_dx_dri | 0x0e0e0e0e |
| dram_dx_odt | 0x08080808 | | |
| dram_tpr0/1/2 | 0x1b / 0x33 / 0x3 | dram_tpr5/6/8/11 | 0x4 / 0x72 / 0x9 / 0x24 |
| dram_tpr3/4/7/9/10/12/13 | 0 | | |
| dram_mr0 | 0x30fa | dram_mr1 | 0x04 |
| dram_mr3/mr4 | 0x34 / 0x03 | dram_mr11/12/14/22 | 0x04 / 0x72 / 0x09 / 0x24 |
| dram_mr2/5/6/13/16/17 | 0 | | |

Consistency: mr12==tpr6 (0x72), mr14==tpr8 (0x09), mr22==tpr11 (0x24).
For platform agent: compare against our SPL 672 MHz LPDDR4 config.

## PMIC (AXP2202, alias AXP717 silicon)

- `soc/twi@0x07081400/pmu`: compatible `x-powers,axp2202`, reg 0x34.
- Children: `powerkey@0` (event0 `axp2202-pek`), `regulators@0`
  (dcdc1-4, aldo1-4, bldo1-4, cldo1-4, cpusldo, rtcldo, vmid,
  drivevbus), `bat-power-supply`, `usb_power_supply`.
- DT only carries min/max ranges (e.g. dcdc2 500000-3400000 uV);
  live setpoints are in `regulators.txt` (DCDC2 940 mV, DCDC3
  1100 mV — exact match to our SPL).
- `axp2202-parameter/select` = `battery-model` (curve selector).
- Sibling nodes: `charger0` (pmu_safe_vol), `power_sply` (rail
  modes: dcdc1_mode, dcdc2_mode, ntc_status, ...).

## Audio

- `soc/codec@0x05096000`: `allwinner,sunxi-snd-codec`, status okay.
- Machines: `codec_mach` + `codec_plat` (card0 audiocodec),
  `ahub0..3_mach/plat`, `ahub_dam_mach/plat@0x05097000` (card1,
  no PCMs in /proc), `hdmi_codec` (card2 ahubhdmi).
- Matches live `/proc/asound/cards` 1:1.

## Display (panel identified!)

- `soc/disp@01000000`: `allwinner,sunxi-disp`, okay.
- `soc/lcd0@01c0c000`: `allwinner,sunxi-lcd0`, okay (lcd1 also okay).
- `lcd_driver_name` = **`fog_fj035fhd05_v1`** — stock panel module ID.
  Platform: verify our OOT init sequence targets this module
  (likely nv3052c-based 3.5" 640x480; confirm IC == init).
- Timings: 640x480, ht=770 (hfp=64), hbp=46, hspw=20, vt=528
  (vfp=30), vbp=14, vspw=4, dclk=24 MHz, hv-if RGB (if=0),
  sync polarity 3, clk phase 2, frm=1, gamma/cmap off.
- Physical: 150x94 mm (matches stale fb.cfg dump exactly).
- Backlight: pwm ch0, 50 kHz, used=1, default level 50.
- Note: NO `/sys/class/backlight` on stock; brightness goes through
  the disp driver (dmenu ioctl) — and `brightCtrl.bin` is absent
  from this unit's `/mnt/vendor/bin`.

## Input (key codes, polled 20 ms)

`soc/gpio_keys` (`gpio-keys-polled`), `poll-interval` = 20:

| Key | Code | Key | Code |
|---|---|---|---|
| A/B/X/Y | 304/305/306/307 (BTN_SOUTH/EAST/NORTH/WEST) | L1/R1 | 308/309 |
| Start/Select | 311/310 | Menu | 312 (BTN_MODE) |
| L3/R3 | 313/316 | L2/R2 | 314/315 |
| UP/DOWN | 17 (ABS_HAT0Y) | Left/Right | 16 (ABS_HAT0X) |
| Vol+/Vol- | 115/114 | | |

Plus `A0_gpio`/`A1_gpio` + `adc-en`/`amux-en` (analog sticks via
GPADC). UI: cross-check `evdev2jive.map` against this table, esp.
L2/R2 = 314/315 and hat-style dpad (16/17).

## GPU / video / wireless

- `gpu@0x01800000`: `arm,mali-midgard` (no status prop = always on).
- Video blocks: `ve@01c0e000`, `vp9@01c00000`, `deinterlace`,
  `g2d@01480000`, `tr@01000000` (rotation), `ce@1904000`.
- `wlan` (`allwinner,sunxi-wlan`, chip_en/power_en GPIOs),
  `bt` + `btlpm` nodes; `hdmi@06000000` + `tv0@01c94000`.
- UARTs 0-5 present (`uart@05000000` = ttyS0 console).

## PMIC-adjacent / misc of interest

- `rtc@51` on twi5 (RTC used by loadapp.sh date check).
- `s_cir@07040000` (IR), `gpadc`, `thermal_sensor`.
- `boot_disp`, `card0/2_boot_para`, `dram_para1..15` under soc
  (boot0 leftovers — the TPR source of truth lives here too).
- `__symbols__` present (phandle lookups available).
