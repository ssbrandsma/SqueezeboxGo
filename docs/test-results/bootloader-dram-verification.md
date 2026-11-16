# Bootloader DRAM verification (LPDDR4)

Date: 2026-11-16. Verifier: Agent 0 (Lead). Method: source inspection of
the exact pinned U-Boot commit our SPL was built from — the filename
`ddr4.img` was treated as a claim, not evidence.

## Result: PASS — ddr4 SPL performs LPDDR4 initialization

Pinned source `u-boot v2026.10` commit `55084065` (= `pins.env`
`UBOOT_SHA`, re-verified by fresh clone) contains, verbatim:

`configs/anbernic_rg35xx_h700_defconfig`:

- `CONFIG_SUNXI_DRAM_H616_LPDDR4=y` (type select)
- `CONFIG_DRAM_CLK=672` (672 MHz DRAM clock → 1344 MT/s, within the
  K4F8E304HB 3200+ MT/s rating)
- `CONFIG_DRAM_SUNXI_DX_ODT=0x08080808`,
  `CONFIG_DRAM_SUNXI_DX_DRI=0x0e0e0e0e`,
  `CONFIG_DRAM_SUNXI_CA_DRI=0x0e0e`,
  `CONFIG_DRAM_SUNXI_ODT_EN=0x7887bbbb`,
  `CONFIG_DRAM_SUNXI_TPR2=0x1`, `TPR6=0x40808080`, `TPR10=0x402f6633`,
  `TPR11=0x1b1f1e1c`, `TPR12=0x06060606`,
  `CONFIG_DRAM_SUNXI_PHY_ADDR_MAP_1=y` (TPR0/TPR13 at Kconfig default 0;
  the H616 driver does not consume TPR13)
- `CONFIG_AXP717_POWER=y`, `CONFIG_AXP_DCDC2_VOLT=940`,
  `CONFIG_AXP_DCDC3_VOLT=1100` (DCDC3 = 1.1 V matches LPDDR4 VDD2/VDDQ)

Our `build-uboot.sh` ddr4 path runs this defconfig **unmodified**
(no fragment), and `fetch.sh` asserts the defconfig's presence at the
pinned tag — so the consumed file is exactly the one quoted above.

## Code-path trace (same commit)

- `arch/arm/mach-sunxi/dram_sun50i_h616.c:1322` — `dram_para`:
  `.clk = CONFIG_DRAM_CLK`, `.type = SUNXI_DRAM_TYPE_LPDDR4`
  (`#elif` on our symbol), TPR/ODT/DRI fields from defconfig.
- Type-switched init: LPDDR4 `phy_init[]` tables (lines 242-250, 261-269),
  ODT config, write-leveling, read/write training (`mctl_phy_*` branches
  on `SUNXI_DRAM_TYPE_LPDDR4` throughout).
- `board/sunxi/board.c: sunxi_board_init()` — `CONFIG_AXP717_POWER` block
  calls `axp_set_dcdc2(940)` + `axp_set_dcdc3(1100)` (lines 605-609) via
  the AXP717 table in `drivers/power/axp_spl.c`, **before**
  `gd->ram_size = sunxi_dram_init()` (line 656) in the same function.
  Rails before training: correct order.
- `sunxi_dram_init()` auto-detects rank width/size and hangs on 0 bytes,
  so a wrong type fails loudly at SPL (no silent mis-train).

## Binary corroboration (weaker, consistent)

Both shipped SPLs identify as `U-Boot SPL 2026.10 (Nov 10 2026 …)`,
758281 bytes each, differing in 24793 bytes — same codebase, different
compiled-in DRAM tables/paths. `strings` shows DRAM error/training
messages but no type marker (expected: the type is a compiled constant).

## Residual risks (need hardware)

- TPR/DX/ODT values come from the upstream defconfig author, tuned for
  *an* RG35XX-H LPDDR4 board — confirm on V4.0 via first boot
  (`DRAM: 1024 MiB` in SPL output) and stability soak.
- Exact AXP717 rail→net mapping (which rail feeds DRAM VDD2/VDDQ vs SoC)
  needs schematics or the stock boot0 PMU print; voltages match LPDDR4.
- `ddr3` image (fragment switches to `SUNXI_DRAM_H616_DDR3_1333`) is
  unvalidated: no DDR3 unit sighted, TPR unconfirmed. Do not ship as
  bootable without a DDR3 boot log.
