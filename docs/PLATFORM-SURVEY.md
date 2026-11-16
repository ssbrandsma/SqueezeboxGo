# Platform survey — why this Linux foundation

WP0 evaluated five possible Linux bases for the RG35XX H (Allwinner H700)
against working display, controls, audio, Wi-Fi, power, source
availability, reproducibility, and licensing. This record preserves the
evidence so the choice never has to be re-researched. Decision:
[ADR-0001](decisions/0001-linux-foundation.md) — custom mainline-based
image following the ROCKNIX H700 pattern.

## 1. Mainline Linux + U-Boot (chosen as base)

- `torvalds/linux` carries `sun50i-h700-anbernic-rg35xx-h.dts`, including
  `-plus.dts` and `-2024.dts`: 4-channel adc-joystick (gpio-mux + GPADC),
  gpio-keys, AXP717 PMIC, RTL8821CS SDIO Wi-Fi (mmc1 + pwrseq) and BT
  (uart1), sun4i-codec LINEOUT + headphone detect, Mali-G31 (Panfrost).
- U-Boot master carries `anbernic_rg35xx_h700_defconfig`
  (`MACH_SUN50I_H616`, LPDDR4 params, AXP717) + ATF BL31 for `sun50i_h616`.
- **Gap**: no panel/display nodes in any H700 DTS — display is carried
  out-of-tree (our `kernel/patches/0001..0005` + `rg35xx-h-display-oot.dtsi`).
- Verdict: best base — real source, reproducible, maintainable — plus a
  small owned OOT display package instead of binary blobs.

## 2. ROCKNIX (pattern reference, not forked)

- JELOS fork, H700 device dir: cortex-a53, U-Boot+ATF, Panfrost G31,
  mainline kernel (≈7.1.x) with ~31 OOT patches (generic MIPI panel,
  joypad amux-count=4, suspend/USB/OTG), DTB installed as `dtb.img`,
  separate DDR3/DDR4 release images — the exact shape our image follows.
- Kernel config reference: `RTW88_8821CS`, Panfrost, SUN8I HDMI/MIXER,
  SUN4I DRM+DSI, AXP20X battery/ADC, JOYDEV (mirrored in our fragment).
- **Why not forked**: release notes list non-commercial-only components
  and branding is CC BY-NC-SA; GPL patch *techniques* are reusable with
  attribution, the distribution itself is not a clean base for us.

## 3. muOS (rejected: closed core)

- Device dir `internal/device/rg35xx-h` (audio/battery/board/cpu/gpu/screen
  configs) + SDL2 frontend (GPL-3.0 UI — genuinely open).
- **Fatal**: `kernel.bin` is a binary ARM64 `Linux version 4.9.170`
  (Linaro GCC 5.3); no kernel/bootloader source anywhere in the MustardOS
  org, no rootfs build repo. Panel reference only: `sunxi.dts` names the
  `fog_fj035fhd05_v1` 640x480 RGB panel + PWM-ch0 backlight timings (BSP
  syntax, timing reference, not reusable as-is).

## 4. KNULLI (rejected: closed BSP + dead-end graphics)

- Buildroot/Batocera derivative, `knulli-h700.board`: kernel 4.9.170
  (orangepi-xunlong sun50iw9 BSP), ATF disabled, `mali-g31-fbdev`
  (fbdev, no DRM/KMS — incompatible with our SDL2/KMSDRM plan), genimage
  layout (GPT, boot0@256K, boot_package.fex@16MB, FAT boot, vfat data).
- **Fatal**: releases embed stock-extracted bootloader/kernel; per the
  KNULLI wiki Anbernic publishes no source, so the whole BSP chain is
  unreproducible vendor binaries.

## 5. Stock Anbernic firmware (rejected: no source)

- Official portal (`win.anbernic.com`, 64-bit Linux); community
  StockOS-Modification images exist for H700 — but no kernel/U-Boot
  source is published, so nothing is verifiable or maintainable.

## 6. Hardware enablement status (this project)

| Subsystem | Mainline driver | Our state |
|---|---|---|
| Display (DE/TCON/DSI/nv3052c/PWM) | partial (needs OOT) | OOT series + DT, compile-verified, HW-gated |
| D-pad/buttons | gpio-keys | in DTS; evdev→SDL mapper ships |
| Sticks | adc-joystick + GPADC | in DTS; direction/flip need evtest on HW |
| Audio (codec/HP) | sun4i-codec + LINEOUT/hp-det | asound.conf + arbiter ship; live validation HW-gated |
| Wi-Fi/BT | RTW88_8821CS + uart BT | kernel fragment + firmware-realtek; assoc. HW-gated |
| Power/battery | AXP717 + ADC | fragment + BSP applet probes; readings HW-gated |
| USB host/OTG | musb/sunxi-phy | fragment set; DAC hotplug HW-gated |
| GPU | Panfrost (Mali-G31) | kernel on; Mesa userspace deferred until GLES is measured |

## 7. What each rejected option still gave us

- ROCKNIX: kernel-config values, DTB-as-`dtb.img` install convention,
  DDR3+DDR4 dual-image strategy, OOT patch techniques (ported minimally
  with attribution into `kernel/patches/`).
- muOS: panel identity (`fog_fj035fhd05_v1`, 640x480 RGB, PWM-ch0) and
  timing reference; SDL2-on-DRM/KMS confirmation for the graphics plan.
- KNULLI: GPT/FAT/ext4 layout sanity reference; warning case for
  binary redistribution (their wiki documents Anbernic's missing source).
- Stock: proof that 64-bit Linux + our mainline drivers target the right
  hardware (H700 = H616 class + ATF BL31).

## 8. Revisit triggers (when to re-evaluate)

- A vendor kernel source drop (Anbernic or Allwinner BSP release) would
  reopen the panel-driver question — but mainline + owned OOT stays
  preferable unless the drop covers the nv3052c chain better.
- If ROCKNIX relicenses the non-commercial parts, forking their H700
  device tree becomes viable and would shrink our OOT maintenance.
- Mainline gaining the panel nodes upstream would let us delete
  `0004/0005` and the `.dtsi` overlay entirely — check each kernel bump.
