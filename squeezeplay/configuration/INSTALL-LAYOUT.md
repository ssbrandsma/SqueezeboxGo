# /opt/squeezeplay install layout (WP2, Agent 2 Core)

Exact on-target tree produced by `Makefile.linux-aarch64` (`PREFIX=/opt/squeezeplay`,
`DESTDIR` staging), as verified from the WP2 aarch64 build
(`squeezeplay-aarch64-9.0.0.tgz`, 23533594 bytes, sha256 `908a5423…01d9`;
see `docs/test-results/wp2-core.md`). Target glibc provides `libc/m/dl`;
everything else Jive needs ships here.

```
$PREFIX = /opt/squeezeplay
$PREFIX/
  bin/
    jive                 aarch64 player binary (RUNPATH $PREFIX/lib)
    jive_alsa            aarch64 ALSA backend, fork+exec'd by jive (needs libasound.so.2)
    lua / luac           aarch64 Lua 5.1.5 (lua links shared liblua; luac static)
    lprof                lua profiler driver
    squeezeplay.sh       launcher (LD_LIBRARY_PATH + USEALSA* knobs; see contract)
    sdl-config, *-config, cjpeg/djpeg/..., xmlwf, freetype-config
                         build-time helpers; PRUNE on the image (Agent 1)
    [image adds: rg35xxh service wrapper + default logconf.lua]
  lib/
    liblua.so            PUC Lua 5.1.5 shared (patch 0001; rpath $PREFIX/lib)
    libSDL-1.2.so.0      build-ABI SDL (runtime: replaced/shadowed by Agent 4
                         sdl12-compat on SDL2/KMSDRM - same SONAME)
    libSDL_image-1.2.so.0  libSDL_ttf-2.0.so.0  libSDL_gfx.so.0
    libFLAC.so.8  libogg.so.0  libmad.so.0  libvorbisidec.so.1
    libfdk-aac.so.2      codecs for local decode (libvorbisidec = Tremor integer Vorbis)
    libexpat.so.1  libfreetype.so.6  libjpeg.so.9
    libpng12.so.0 (+libpng.so.3 compat)  libz.so.1
    libtolua++.so        jive UI bindings runtime
    lua/5.1/*.so         Lua C modules (cpath $PREFIX/lib/lua/5.1/?.so):
                         cjson, lfs, lxp, md5, sha1, profiler, rtmp,
                         zipfilter, socket/core, mime/core, unicode/core
    [WP2-next: rg35xxh_bsp.so - BSP C module, same dir]
  share/
    jive/
      applets/           49 stock applet dirs (AboutJive..WQVGAsmallSkin),
                         incl. skins QVGA*/WQVGA*/FullscreenSkin/JogglerSkin
      [image adds: applets/SqueezeboxRG35XXH/ (BSP applet, this tree)
                   skins/RG35XXHBaseSkin/ (Agent 4, replaces desktop default)]
      jive/              framework Lua (JiveMain, AppletManager, System,
                         ui/*, slim/*, net/*, audio/*, utils/*)
      fonts/             FreeSans.ttf, FreeSansBold.ttf (DejaVu 2.37)
    lua/5.1/             Lua sources: loop/*, socket/*, ltn12, mime, lxp/lom
    man/ doc/ aclocal/   docs; PRUNE on the image
  include/  man/         headers/pkgconfig; PRUNE on the image (dev only)
```

## Size reference (staging, WP2 build)

- Whole staging tree: ~44 MB (27 MB `share/jive`, rest libs+bins).
- Prunable dev payload (`include/`, `man/`, `share/man`, `share/doc`,
  `*-config`, jpeg tools): ~4.5 MB, plus unversioned `.so` dev symlinks.

## Runtime resolution notes

- `jive`, `jive_alsa`, `lua` carry `RUNPATH [$PREFIX/lib]` exactly; no
  staging (`/tmp/...`) leakage (verified `readelf -d`).
- `jive_alsa` is the only binary needing target `libasound.so.2` (ships in
  the image rootfs, not here); `jive` itself has no ALSA NEEDED (it
  fork+execs `jive_alsa` from its own bin dir).
- Lua search paths are bootstrapped by `jive.c` relative to the executable
  (`../share/lua/5.1`, `../lib/lua/5.1`), so the tree relocates under any
  `$PREFIX` as long as `bin/` and `lib/`/`share/` stay siblings.
- `squeezeplay.sh` env knobs (contract): `USEALSA_DEVICE/SAMPLE_SIZE/
  BUFFER/PERIOD/NOMMAP/PCM_TIMEOUT`, `SQUEEZEPLAY_NOPLAYBACK`, `UTMAC`,
  plus WP2 `AUDIO_OWNER_BIN` (patch 0006, opt-in audio-owner gate).
