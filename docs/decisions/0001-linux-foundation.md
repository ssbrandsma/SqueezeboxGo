# ADR-0001 — Linux foundation: custom mainline-based image (ROCKNIX pattern)

Date: 2026-11-15. Status: accepted.

## Context

Need working display, controls, audio, Wi-Fi, power, reproducible build.
Candidates: ROCKNIX, muOS, KNULLI, stock Anbernic, mainline.

## Evidence

- Mainline has `sun50i-h700-anbernic-rg35xx-h.dts` (+plus/+2024): adc-joystick,
  gpio-keys, AXP717, RTL8821CS Wi-Fi/BT, sun4i-codec LINEOUT+hp-det, GPU.
  Gap: no panel nodes (display carried out-of-tree).
- U-Boot master has `anbernic_rg35xx_h700_defconfig` (H616+ATF BL31, LPDDR4, AXP717).
- ROCKNIX H700: mainline kernel 7.1.2, RTW88_8821CS, Panfrost, DRM/DSI,
  ~31 OOT patches (generic MIPI panel, joypad, suspend/USB/OTG), DDR3+DDR4 images.
- muOS/KNULLI/stock: closed 4.9.170 BSP binaries, no kernel/u-boot source.

## Decision

Build a custom mainline-based image following the ROCKNIX pattern
(mainline kernel + vendored OOT display/joypad patches, U-Boot+ATF, DTB→dtb.img).
Own branding and rootfs; reuse GPL components with attribution only.

## Consequences

- Reproducible, maintainable, no binary blobs; must maintain OOT panel DTS+driver.
- ROCKNIX branding is CC BY-NC-SA with non-commercial parts: do not rebrand/reuse those.
