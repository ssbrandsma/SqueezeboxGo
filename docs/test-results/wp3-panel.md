# WP3 panel test results (display bring-up package)

Branch: `wp3/panel`. Date: 2026-11-16. Verdict: **compile-verified,
hardware-gated** — no boot/picture claims (no physical RG35XX-H).

## 1. Source identification (read-only /tmp work)

- ROCKNIX `distribution.git` master (`next` @ `397e1ed`, sparse
  `projects/Allwinner`): 62 linux patches, all H3/H5/A64/H6 — **no H700
  or panel set**. Single branch `next`. WP1's "absent from Allwinner"
  note confirmed; ROCKNIX is NOT the port source (also avoids any
  CC BY-NC-SA contact entirely).
- Panel driver: NO port needed. `drivers/gpu/drm/panel/
  panel-newvision-nv3052c.c` is in-tree at v7.3.4 with
  `anbernic,rg35xx-plus-panel` = WL-355608-A8 (kikuchan98's Rev6
  entry, `Kconfig DRM_PANEL_NEWVISION_NV3052C`, needs SPI +
  BACKLIGHT_CLASS_DEVICE, selects DRM_MIPI_DBI). Binding doc
  `anbernic,rg35xx-plus-panel.yaml` in-tree.
- Port base: Ryan Walklin's GPL lore series "arm64: dts: allwinner:
  h616: add LCD timing controller and display engine support"
  (2025-02-16, 8 patches, Jernej Skrabec co-author, Philippe Simons
  **Tested-by on RG35XX-H**):
  `https://lore.kernel.org/linux-arm-kernel/20250216092827.15444-1-ryan@testtoast.com/`
- At v7.3.4 already merged from that direction: TCON clock defines,
  DE33 clk (`ccu-sun8i-de2.c`), DE33 mixer match, `RST_BUS_LVDS`,
  R40 TCON-TV quirks, PWM clocks/resets in the H616 CCU driver.
  Still missing (= this package): DE33 bus match, R40 LCD quirks,
  all display DT nodes, PWM match/node.
- Pinctrl verified in `pinctrl-sun50i-h616.c`: PD0-27 `lcd0`,
  PD0-19 `lvds0/1`, PD28 `pwm0`. TCON addrs/IRQs (0x6510000,
  0x6511000/IRQ64, 0x6515000/IRQ66) match H6 precedent + the
  H-tested series. SRAM: v7.3.4 already has `sram_c` with the
  a64 fallback, so the bus claims `&sram_c` (no extra section).

## 2. Patch application

Fresh `linux-7.3.4.tar.xz` (sha256 `b11b6df8…` verified) + series
applied exactly as `build-kernel.sh` does
(`patch -p1 --forward --no-backup-if-mismatch`): 0001-0005 all
**apply clean, no fuzz, no .rej**.

## 3. DTB builds (kernel `dtbs` target, ARCH=arm64)

- `sun50i-h700-anbernic-rg35xx-h.dtb`: builds, **0 warnings**,
  32427 bytes.
- Siblings sharing `sun50i-h616.dtsi` (regression sweep): all 14
  build, **0 warnings** — 2024, Plus, SP, h313 x2, h616 x4
  (x96-mate, cb1-manta, bigtreetech-pi, orangepi-zero2),
  h618 x4 (zero2w, transpeed-8k618-t, chameleon, longanpi-3h,
  orangepi-zero3). Total 15/15 DTBs, 0 warnings.
- Decompiled-DTB check: display-engine `okay`, mixer0 present,
  pwm `h616+h6` compatible, tcon-top + lcd0 (IRQ 64, `okay`) +
  tv0 (IRQ 66, `disabled`), pwm-backlight `pwms = <&pwm 0 50000
  0>`, panel `anbernic,rg35xx-plus-panel` @3.125 MHz SPI,
  10 `remote-endpoint` links incl. panel<->tcon_lcd0_out.
- Standalone `dtc -I dts -O dtb` (dtc 1.7.0, system): byte-identical
  DTB, 3 warnings — all dispositioned, none ours: (a) `/soc` unit
  name = pre-existing upstream style, suppressed by kbuild default
  flags; (b+c) 2x `graph_child_address` on tcon_top ports = also
  emitted by the PRISTINE in-tree H6 tcon_top (verified), i.e.
  accepted upstream pattern + newer-dtc noise. In-tree dtc 1.7.2
  does not emit them. Kept H6-identical deliberately.

## 4. Driver cross-builds (aarch64, project KCFLAGS)

Config: arm64 defconfig + project fragment + `display-defconfig.delta`
(all delta symbols accepted: NV3052C=y, SPI_GPIO=y,
REGULATOR_FIXED_VOLTAGE=y; TCON_TOP=y via default; PWM_SUN4I=y,
SUN50I_DE2_BUS=y). Cross-built, **0 warnings**, all ELF aarch64:

- `drivers/bus/sun50i-de2.o` (0001), `sun4i_tcon.o` (0002),
  `pwm-sun4i.o` (0003)
- `panel-newvision-nv3052c.o`, `spi-gpio.o`, `pwm_bl.o`, `fixed.o`

Shipping form is built-in (=y, panel at boot without initramfs), so
.o (not .ko) is the operative artifact. A modular side-attempt
(panel=m, `M=` build) compiles but modpost cannot link without a
full-tree Module.symvers — environmental, not a code defect (fails
identically for pristine panel modules).

## 5. Full build

`Image modules dtbs` (defconfig + fragment + delta, project KCFLAGS):

- Exit 0. `Image` 53,901,824 bytes (sha256 `745001ee…`), 1675 `.ko`
  modules, all DTBs incl. `sun50i-h700-anbernic-rg35xx-h.dtb`
  (32427 bytes). **Zero warnings** in the full build log.
- Toolchain note: no docker/cross-compiler on the host, so the pinned
  Debian set was reproduced user-space in /tmp (Ubuntu 24.04
  `gcc-aarch64-linux-gnu 13.3.0` + binutils + libc6-dev-arm64-cross,
  dtc 1.7.0, flex/bison/m4, libssl-dev — `apt-get download` only,
  nothing installed, nothing committed).

## 6. NOT RUN (needs hardware)

- Boot to 640x480 picture, backlight PWM period/polarity (B1),
  kmsdrm blanking + mode (B2), evdev/ALSA/Wi-Fi no-regression.
  Runbook: `platform/rg35xx-h/device-tree/BRINGUP_PANEL.md`.
