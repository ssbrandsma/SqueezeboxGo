# Device tree (RG35XX H)

## In-tree chain (linux v7.3.4, verified)

`sun50i-h700-anbernic-rg35xx-h.dts` -> `-plus.dts` (mmc1 Wi-Fi, uart1 BT) ->
`-2024.dts` (gpio-keys, codec, regulators, USB) -> `sun50i-h616.dtsi`.

Covered in-tree: sticks (`adc-joystick`), buttons (`gpio-keys`), AXP717,
RTL8821CS SDIO+BT nodes, sun4i-codec LINEOUT + hp-detect, USB, GPU, RTC,
thermal, cpufreq OPP. Missing in-tree: the **entire display pipeline**
(no DE/mixer/TCON/DSI/PWM/panel nodes anywhere in h616.dtsi or the board
chain) — see `../kernel/patches/oot-patch-list.md`.

## OOT files (this directory)

- `rg35xx-h-display-oot.dtsi` — FINALIZED WP3 display pipeline (board-level:
  PWM backlight, LCD regulator, spi-gpio panel, enables). DTB build clean;
  hardware picture still gated. Master copy, mirrored into the kernel tree
  by `../kernel/patches/0005` (keep in sync).
- `rg35xx-h-display-oot.dtsi.template` — HISTORICAL placeholder, superseded
  by the finalized `.dtsi` above. Kept for WP1/WP2 archaeology only;
  build-kernel.sh never picks it up.
- `BRINGUP_PANEL.md` — panel debug runbook (deferred probe, PWM backlight,
  kmsdrm blanking) for first boot on hardware.
- Final include order: -H.dts -> -plus -> -2024 -> in-tree h616.dtsi -> OOT
  dtsi (the OOT include sits at the end of the -H.dts include chain so all
  SoC labels exist before use).

## Build (WP3: DISP-SOC-01 + DISP-PANEL-01 landed, HW-gated)

```sh
# inside the kernel tree with OOT files copied to dts/allwinner/:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  allwinner/sun50i-h700-anbernic-rg35xx-h.dtb
# installed on the FAT boot partition as dtb.img (see build/image/).
```

DTB is installed as **`dtb.img`** (ADR-0001): `boot.scr` loads it to
`${fdt_addr_r}`; no U-Boot embedded DTB override.

## Validation gates (each needs evidence in `docs/test-results/`)

1. `dtc -I dts -O dtb` clean build, zero warnings. PASS WP3 via the kernel
   `dtbs` target (15/15 h616-family DTBs, 0 warnings); standalone dtc 1.7.0
   shows only pre-existing/precedent warnings (see `docs/test-results/wp3-panel.md`).
2. Boot on hardware: stable 640x480, correct colors, backlight control works.
   NOT RUN (no hardware; runbook: `BRINGUP_PANEL.md`).
3. No regression: evdev + ALSA + Wi-Fi probes still pass with OOT DTB.
   NOT RUN (needs hardware; sibling DTBs build clean).
