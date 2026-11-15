# OOT kernel patch list (RG35XX H, linux v7.3.4)

Status: WP3 — first patch series LANDED (`series`: 0001-0005, display
bring-up, compile-verified + HW-gated). `build-kernel.sh` applies `series`
in order. Patch format: see `0000-TEMPLATE.patch`. License rule (ADR-0001):
GPL components with attribution only; no ROCKNIX CC BY-NC-SA /
non-commercial material.

WP3 source findings (2026-11-16, evidence in `docs/test-results/wp3-panel.md`):
- F1: ROCKNIX master (`next` @ `397e1ed`) carries NO H700/H616 display
  panel set (62 patches, H3/H5/A64/H6 only) — confirmed the WP1 suspicion.
  The port source is instead the GPL lore series below, not ROCKNIX.
- F2: Panel driver needs NO port: `panel-newvision-nv3052c.c` is in-tree
  at v7.3.4 with `anbernic,rg35xx-plus-panel` (kikuchan98's Rev6 /
  WL-355608-A8 entry). Defconfig delta only (`display-defconfig.delta`).
- F3: Port base = Ryan Walklin's lore series "h616: add LCD timing
  controller and display engine support" (2025-02-16, 8 patches, Jernej
  Skrabec co-author, Tested-by Philippe Simons ON RG35XX-H):
  `https://lore.kernel.org/linux-arm-kernel/20250216092827.15444-1-ryan@testtoast.com/`
  At v7.3.4, series patches 3/8 (TCON clock defines), DE33 clk/mixer
  drivers and the LVDS reset are already merged; 1/8, 4/8 (drivers) and
  2/5/6/7/8 (DTS) are ported here with review-driven fixes (see 0004/0005
  headers).

Evidence base (all verified 2026-11-15 at the pinned tags):
- E1: `sun50i-h700-anbernic-rg35xx-h.dts` (119 lines) includes `-plus.dts`
  (46 lines, mmc1 Wi-Fi + uart1 BT) includes `-2024.dts` (320 lines,
  gpio-keys, codec, regulators, USB) includes `sun50i-h616.dtsi`.
- E2: `sun50i-h616.dtsi` (1141 lines) has **zero** display nodes: no DE/mixer,
  TCON, DSI, DPHY, PWM, HDMI. The whole display pipeline is OOT, not just
  panel nodes.
- E3: no `panel|dsi|mipi|tcon|backlight` matches in the RG35XX DTS chain.
- E4: audio in place in-tree: `&codec` (LINEOUT->Speaker/Headphone via
  74HC4052D, PA gpio PI5, hp-det PI3) + `sun50i-h616-codec` in h616.dtsi.
- E5: U-Boot v2026.10 ships `anbernic_rg35xx_h700_defconfig` (LPDDR4) and
  `SUNXI_DRAM_H616_DDR3_1333` as the DDR3 timing class.

## Patch classes

| ID | Title | Why (evidence) | Reference to port from | Status |
|----|-------|----------------|------------------------|--------|
| DISP-SOC-01 | H616/H700 display SoC nodes (DE33, mixer, TCON TOP/LCD/TV, PWM, display clocks) | E2: none in-tree | lore H616 LCD series (F3); 0001-0004 | LANDED WP3 (compile-verified, HW gate) |
| DISP-PANEL-01 | RG35XX-H board panel nodes: 640x480 RGB panel + PWM-ch0 backlight + DE/TCON endpoint wiring | E3, docs/hardware.md panel note; lore series Tested-by on H | lore series 7/8+8/8 adapted (PWM backlight, -H-only); master: `device-tree/rg35xx-h-display-oot.dtsi`; in-tree via 0005 | LANDED WP3 (compile-verified, HW gate) |
| DISP-BRINGUP-01 | simplefb/simpledrm handoff or early splash framebuffer | needed for splash-before-KMS story | ROCKNIX splash mechanism (pattern only) | TODO (WP2) |
| JOY-01 | adc-joystick/stick tuning IF in-tree defaults prove wrong on HW | in-tree `adc-joystick` + `gpio-keys` look complete (E1) | none yet; evdev probe on HW decides | HOLD |
| PWR-01 | AXP717 suspend/resume + power-button behavior | standby/wake contract (interface-contracts.md HAL) | ROCKNIX suspend patches (pattern only) | TODO (WP2, HW gate) |
| USB-01 | OTG/host role + VBUS quirks IF in-tree proves wrong | in-tree usbphy/ehci/ohci + `reg_vcc5v0_usb` look complete (E1) | none yet | HOLD |
| WIFI-01 | RTW88_8821CS quirks + firmware packaging notes | in-tree DTS (E1) + `CONFIG_RTW88_8821CS` exist; firmware blobs ship in rootfs | linux-firmware `rtw88/rtw8821c_fw.bin`, `rtl_bt/rtl8821c_*` | TODO (WP2) |

## Landed series (WP3, `series` 0001-0005)

| File | Content | Validation |
|------|---------|------------|
| 0001-bus-sun50i-de2-h616-de33.patch | DE33 bus match (lore 1/8, verbatim) | applies clean; sun50i-de2.o cross-built, 0 warnings |
| 0002-drm-sun4i-tcon-r40-lcd.patch | R40 LCD quirks+match (lore 4/8, verbatim) | applies clean; sun4i_tcon.o cross-built, 0 warnings |
| 0003-pwm-sun4i-h616-compatible.patch | H616 PWM match, H6 data (Squeezebox OOT) | applies clean; pwm-sun4i.o cross-built, 0 warnings |
| 0004-arm64-dts-h616-display-soc.patch | SoC display nodes (lore 2/5/6 + PWM, review-fixed) | 15/15 h616-family DTBs build, 0 warnings |
| 0005-arm64-dts-rg35xx-h-display-oot.patch | -H OOT display dtsi + include (lore 7/8+8/8 adapted) | H DTB builds; graph verified in decompiled DTB |
| display-defconfig.delta | =y delta for Agent 1's config fragment (NOT a kernel patch; do not list in `series`) | olddefconfig accepts all; panel/spi/regulator .o cross-built |

Full `Image modules dtbs` result: see `docs/test-results/wp3-panel.md`.
Hardware probe: NOT RUN (no RG35XX-H); runbook
`device-tree/BRINGUP_PANEL.md`.

## Rules for landing a patch here

1. One logical change per file, `NNNN-short-name.patch`, listed in `series`.
2. Header: `From:`, `Subject:`, `Upstream-Status:` (Pending/Backport/Denied +
   link), `Signed-off-by:`. GPL-compatible source with attribution.
3. Validation note: which gate passed (builds at pin / boots on HW / evdev or
   ALSA probe attached in `docs/test-results/`).
4. Rebase onto the pinned tag; no fuzz, no `.rej` (build fails closed).
