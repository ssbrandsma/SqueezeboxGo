# 640x480 skin — 2x bootstrap of the QVGA Radio skin

`RG35XXHBaseSkin` + `RG35XXHLandscapeSkin`: pixel-perfect 2x integer scale of
the Radio's default skin (`QVGAbaseSkin` + `QVGAlandscapeSkin`, the Baby/Radio
default per `SqueezeboxBabyMeta.lua: setDefaultSkin("QVGAlandscapeSkin")`)
from `ralph-irving/squeezeplay@758bc11`.

## Regenerate (deterministic, stdlib-only)

```sh
ui/skins/scale_qvga_2x.py --src /path/to/squeezeplay@758bc11 --out ui/skins
```

The pinned tree is never vendored into git; fetch it to `/tmp` (see
`ui/README.md`). Re-running must be a no-op (`git status` clean) — enforced by
the WP1 validation record.

`resize_master_icons.pl` / `sync_assets.pl` from upstream are dev-only helpers
and are intentionally not carried over.

## What the script does

Lua (`...Applet.lua`, audited line-by-line against the WP0 literal survey):

- Renames applet ids/paths/skin key to `RG35XXH*` (code, strings, imgpath,
  `registerSkin`); default video mode becomes 640x480 at 32 bpp
  (`--video-bpp`, was 16 until live testing proved the stock 16 bpp
  scanout broken on 2026-11-16).
- Doubles every decimal geometry literal (positions, sizes, paddings,
  borders, font sizes, line heights, artwork sizes: `320x320`→`640x640`,
  `143x143`→`286x286`).
- Never touches: hex colors, digits inside identifiers (`sleep_15`, `12h`,
  `POPUP_TEXT_SIZE_1`, `wirelessLevel3`, …), the flags `hidden`,
  `horizontal`, `zOrder`, `frameRate`, the count
  `NOWPLAYING_TRACKINFO_LINES`, the `setVideoMode` bpp arg, `*`/`/`
  operands (`* 5` counts, `/2` half-screen divisors), or `Meta.lua`
  numerics.
- Comments get explicit prose replacements only (no blind doubling, so
  `Copyright 2010` etc. survive).

Images: 2x nearest-neighbor PNG rescale (8/16-bit, color types 0/2/3/4/6,
non-interlaced; palette/`tRNS`/gamma chunks preserved). Any other format
aborts the script loudly.

## Font choice

Keep upstream's **GNU FreeFont FreeSans / FreeSansBold** (`FONT_NAME`
unchanged; sizes doubled by the transform, e.g. text menu 18→36). Rationale:
zero new license surface (already vendored + shipped by upstream under
`src/freefont-*`, GPL with font embedding exception), metrics match the
scaled layout by construction. TTFs ship from the squeezeplay tree at image
build time (`fonts/`); this repo carries no font binaries.

## Install (for Agent 2 / image build)

Install both applet dirs next to the other applets
(`share/applets/RG35XXHBaseSkin`, `share/applets/RG35XXHLandscapeSkin`) and
set the default skin to `RG35XXHLandscapeSkin` in the `rg35xxh_bsp` applet
(the Baby pattern: `jiveMain:setDefaultSkin(...)` in the BSP Meta). The skin
self-selects 640x480 via `Framework:getScreenSize()` with a 640x480 fallback.

## Validation (host)

- `luac -p` (Lua 5.1.5, same as target PUC Lua) on all 4 generated files.
- Differential number audit: every source literal re-lexed and checked
  scaled-vs-excluded (see `docs/test-results/wp1-ui.md`).
- All 467 PNGs: `file` format check, 2x dimension check, pixel round-trip.
- No functional Jive render test on host (needs the full squeezeplay+aarch64
  build); first render check is a WP2 hardware/QEMU item.
