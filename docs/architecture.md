# Architecture

## Selected foundation (WP0)

- **Linux**: custom mainline-based image following the ROCKNIX H700 pattern
  (mainline kernel + out-of-tree display/joypad patches). No closed 4.9.170 BSP blobs.
- **Boot**: U-Boot `anbernic_rg35xx_h700_defconfig` + ATF BL31; DTB installed as `dtb.img`;
  DDR3 and DDR4 image variants.
- **SqueezePlay**: `ralph-irving/squeezeplay@758bc11` full UI + playback engine,
  PUC Lua 5.1.5, new `Makefile.linux-aarch64` (WP1). `squeezeos-squeezeplay` backports only.
- **Audio**: ALSA via `decode_alsa_backend.c` (S32/S24/S16 fallback, hi-res fixes);
  internal sun4i-codec default, `snd-usb-audio` optional; single-owner audio arbiter.
- **Graphics**: SDL 1.2 API via sdl12-compat on SDL2/KMSDRM, X-less, Panfrost GLES.
- **Skin**: custom 640x480 = 2x integer scale of QVGA Radio skin.
- **Input**: evdev → SDL-keyboard mapper (arrows nav, A/Start select, B back,
  shoulders vol/skip, sticks optional scroll).
- **BSP**: `rg35xxh_bsp` cloned from `squeezeplay_fab4` pattern.

## Runtime stack

    U-Boot → Linux → init/services → splash → squeezeplay (Jive+Lua+SlimProto)
                                              → ALSA → sun4i-codec / USB DAC
                                              → SDL/KMS → 640x480 LCD
           services: wifi, audio-owner, now-playing, standalone/*, web mgmt

## Platform abstraction

Device logic lives in `platform/rg35xx-h/` + `rg35xxh_bsp`; generic
Standalone/SqueezePlay logic stays hardware-neutral so Radio (Baby), Touch
(Fab4), RG35XX H, and future ARM64 devices share code. Contracts in
[interface-contracts.md](interface-contracts.md).
