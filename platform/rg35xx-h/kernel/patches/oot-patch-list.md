# OOT kernel patch list (RG35XX H, linux v7.3.4)

Status: inventory + provenance, WP1. No patch files land here until each is
ported to the pinned tree and validated; `patches/series` is created with the
first landed patch and `build-kernel.sh` applies it in order. Patch format:
see `0000-TEMPLATE.patch`. License rule (ADR-0001): GPL components with
attribution only; no ROCKNIX CC BY-NC-SA / non-commercial material.

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
| DISP-SOC-01 | H616/H700 display SoC nodes (DE3, mixer, TCON TOP/LCD, DSI+DPHY, PWM, display clocks) | E2: none in-tree | linux-sunxi WIP H616 DSI series; H616 User Manual display §; ROCKNIX H700 tree (location TBD — absent from `projects/Allwinner` on master 2026-11-15, check branches/forks) | TODO (WP2) |
| DISP-PANEL-01 | RG35XX-H board panel nodes: 640x480 RGB panel + PWM-ch0 backlight + DE/TCON endpoint wiring | E3, docs/hardware.md panel note; muOS sunxi.dts timing reference | muOS sunxi.dts (timing values only, own DTS), template: `device-tree/rg35xx-h-display-oot.dtsi.template` | TODO (WP2, HW gate) |
| DISP-BRINGUP-01 | simplefb/simpledrm handoff or early splash framebuffer | needed for splash-before-KMS story | ROCKNIX splash mechanism (pattern only) | TODO (WP2) |
| JOY-01 | adc-joystick/stick tuning IF in-tree defaults prove wrong on HW | in-tree `adc-joystick` + `gpio-keys` look complete (E1) | none yet; evdev probe on HW decides | HOLD |
| PWR-01 | AXP717 suspend/resume + power-button behavior | standby/wake contract (interface-contracts.md HAL) | ROCKNIX suspend patches (pattern only) | TODO (WP2, HW gate) |
| USB-01 | OTG/host role + VBUS quirks IF in-tree proves wrong | in-tree usbphy/ehci/ohci + `reg_vcc5v0_usb` look complete (E1) | none yet | HOLD |
| WIFI-01 | RTW88_8821CS quirks + firmware packaging notes | in-tree DTS (E1) + `CONFIG_RTW88_8821CS` exist; firmware blobs ship in rootfs | linux-firmware `rtw88/rtw8821c_fw.bin`, `rtl_bt/rtl8821c_*` | TODO (WP2) |

## Rules for landing a patch here

1. One logical change per file, `NNNN-short-name.patch`, listed in `series`.
2. Header: `From:`, `Subject:`, `Upstream-Status:` (Pending/Backport/Denied +
   link), `Signed-off-by:`. GPL-compatible source with attribution.
3. Validation note: which gate passed (builds at pin / boots on HW / evdev or
   ALSA probe attached in `docs/test-results/`).
4. Rebase onto the pinned tag; no fuzz, no `.rej` (build fails closed).
