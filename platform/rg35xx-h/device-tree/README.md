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

- `rg35xx-h-display-oot.dtsi.template` — display pipeline template. Placeholder
  addresses/timings; rename to `.dtsi` only after dtc build + hardware picture.
  Final include order: board dts -> OOT dtsi -> in-tree h616.dtsi.

## Build (WP2, after DISP-* land)

```sh
# inside the kernel tree with OOT files copied to dts/allwinner/:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  allwinner/sun50i-h700-anbernic-rg35xx-h.dtb
# installed on the FAT boot partition as dtb.img (see build/image/).
```

DTB is installed as **`dtb.img`** (ADR-0001): `boot.scr` loads it to
`${fdt_addr_r}`; no U-Boot embedded DTB override.

## Validation gates (each needs evidence in `docs/test-results/`)

1. `dtc -I dts -O dtb` clean build, zero warnings.
2. Boot on hardware: stable 640x480, correct colors, backlight control works.
3. No regression: evdev + ALSA + Wi-Fi probes still pass with OOT DTB.
