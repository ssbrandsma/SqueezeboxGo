# Panel bring-up runbook (RG35XX-H)

First-boot display validation for the WP3 OOT display package
(`rg35xx-h-display-oot.dtsi` + `kernel/patches/0001-0005` +
`display-defconfig.delta`). Status: **compile-verified, hardware-gated** —
no claim below is proven until it runs on a physical RG35XX-H.

Pipeline: DE33 -> mixer0 -> TCON TOP -> TCON LCD0 -> RGB panel
(WL-355608-A8 class, NV3052C controller, SPI init + RGB data),
backlight PWM0 on PD28. Expected mode: 640x480.

## 0. Prerequisites on the bench

- Image with the WP3 panel series applied + delta merged into the kernel
  config (Image + `dtb.img` from the patched tree).
- UART debug header wired (see `docs/hardware.md`) — display failures are
  diagnosed over serial; never assume "dark panel" means "dead board".
- Multimeter on vdd-lcd (3.3 V, PI15-switched) and backlight anode.

## 1. Deferred-probe triage

Symptom: dark panel but serial console alive.

1. `dmesg | grep -iE 'de2|mixer|tcon|nv3052|spi-gpio|pwm|backlight|deferred|probe'`
2. Expected (good) lines:
   - `sun50i-de2 bus@1000000: ...` bound, `sun8i-mixer`, `sun4i-tcon`
     bound, `nv3052c` panel probed, `spi-gpio` + `pwm-backlight` bound.
3. If `-EPROBE_DEFER` loops: find the missing supplier
   (`/sys/kernel/debug/devices_deferred`), usually a clock/reset/phandle
   typo. Check order: ccu -> display_clocks -> mixer0 -> tcon_top ->
   tcon_lcd0 -> panel; pwm -> backlight.
4. If `panel` never probes: verify spi-gpio SCK/MOSI/CS (PI9/PI10/PI8)
   toggle at boot with a scope; check `spi-max-frequency` and `reg_lcd`
   (PI15 high, 3.3 V present).
5. If TCON/LCD fails with clock errors: dump
   `/sys/kernel/debug/clk/clk_summary | grep -iE 'de\b|mixer|tcon|lcd'`
   and confirm `tcon-data-clock` is enabled with a sane rate for
   640x480 (~24 MHz pixel clock region).

## 2. Backlight PWM test (HW gate B1)

The PWM period (50 us) and polarity are first-boot validation items.

1. `ls /sys/class/backlight/` must show the pwm-backlight device.
2. `cat max_brightness; echo <mid> > brightness` — meter the PD28 duty
   cycle; it must track the written level.
3. If the panel stays dark at all levels: try inverted polarity
   (`pwms = <&pwm 0 50000 1>`) and/or 41700 ns period, rebuild DTB.
4. Fallback (proven upstream by Ryan/Philippe): switch the backlight
   node to `gpio-backlight` on PD28 + enable `CONFIG_BACKLIGHT_GPIO`.
   This loses brightness control (HAL contract gap) but unblocks the
   picture. Record the outcome in `docs/test-results/`.

## 3. KMS/DRM blanking and mode check (HW gate B2)

1. `ls /sys/class/drm/` must show `card0-LCD-1` (or similar) with
   `status connected` and `modes` containing `640x480`.
2. `cat /sys/class/drm/card0-LCD-1/mode` after the splash/mode-set.
3. Blanking: `echo 1 > /sys/class/graphics/fb0/blank` (if fbdev
   emulation) or DPMS off via modetest/kmsdrm — backlight must dim
   (PWM duty -> 0) and the panel must resume cleanly on unblank.
4. kmsdrm (SDL2): run the UI smoke (`modetest -M sun4i-drm` if
   available, else the drm_splash painter) and confirm stable 640x480,
   correct colors (RGB888 order — swapped R/B means a panel-format
   mismatch, not a wiring fault), no flicker over 5 minutes.

## 4. No-regression checks (same session)

- evdev: sticks + buttons still enumerate (`/dev/input/event*`).
- ALSA: `aplay -l` still lists the internal codec.
- Wi-Fi: mmc1 + `wlan0` present (PD bank supply change must not break
  other banks — `vcc-pd-supply` only feeds bank D).

## 5. Recording results

Append a dated section to `docs/test-results/wp3-panel.md`:
DTB build ID, Image SHA, dmesg excerpts (probe lines), backlight
sysfs values tested, DRM connector/mode observed, photos of the
picture, and PASS/FAIL per gate B1/B2 + regressions. A green B1+B2
with no regressions promotes this package from HW-gated to proven.
