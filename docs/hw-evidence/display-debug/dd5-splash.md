# dd5 — splash renderer vs menu path (why splash is correct, menu torn)

## The correctly-displayed splash

- File (ONLY splash asset in the tree):
  `/opt/squeezebox-go/jive/share/jive/jive/splash.png` —
  `PNG image data, 480 x 272, 8-bit/color RGB, non-interlaced`
  (7661 B; IHDR verified). `jive/splash640x480.png` does NOT
  exist (the `Can't find image` ERROR at boot is the benign
  fallback to splash.png).
- Renderer: C code in jiveL_initSDL (jive_surface.c), log line
  `jiveL_initSDL:330 Splash jive/splash.png 480x272 Screen
  640x480` — IMG_Load + blit + flip, pre-main-loop, drawn while
  vinfo is still STOCK (boot: 1280x1024x16; first flip lands on
  unclobbered scanout).
- Lua side: JiveMain.lua:385-400 shows a splash WINDOW (2 s timer,
  dismiss on key/scroll) — the only `splash` reference in Lua.
- "Lyrion" appears only in applet strings.txt files (server/software
  naming) — the splash PNG itself is the Lyrion-branded image.

## The torn menu path (owner: language screen readable but
## stride-torn, right-edge line, black fill, unfilled 640x480)

- SDL surface negotiated by jive: 640x480 **32-bit XRGB**
  (`Video mode: 32 bits/pixel 4 bytes/pixel [R<<16 G<<8 B<<0]`)
  from a 16-bpp request (driver UPGRADED 16→32).
- Skin load then calls Framework:setVideoMode(getScreenSize…)
  (lead source trace) — possibly a SECOND SetVideoMode and/or a
  layout size (which skin? RG35XXHLandscapeSkin 640x480 vs a
  WQVGA 480x272 fallback — DISAMBIGUATE from H-LOG skin lines;
  480x272 collides with the splash size, hence the question).
- Either SetVideoMode issues a zeroed-timings FBIOPUT → the vendor
  quirk lands vinfo in a STICKY geometry (512x384x32 / 320x240x16 /
  512-virtual observed) whose pitch/format no longer matches the
  640x480x32 surface jive renders into → alternating scanlines
  (stride mismatch), multicolour artifacts + right-edge line
  (format/offset skew), black regions + unfilled panel (short frame
  in a 640x480 DE layer — cf. dd4's 640x480 UI layer).
- Smoking-gun test (needs device): count `Video mode:` lines in a
  menu-run log (1 = no switch, 2 = skin re-set the mode) + vinfo
  GET at first-flip vs menu-settled (H-LOG + flip-poll; core-dump
  fallback documented in hw-go-redeploy.md §blocked).

## Active-skin evidence so far

- Meta calls jiveMain:setDefaultSkin("RG35XXHBaseSkin"); payload
  skin dir is RG35XXHBaseSkin (lua: RG35XXHBaseSkinApplet/Meta).
  Whether jive SELECTS it (vs stock QVGA/WQVGA fallback) needs the
  H-LOG skin lines or /root/.squeezeplay/userpath/settings/*.lua
  (only DesktopJive/SetupAppletInstaller/SlimDiscovery observed —
  no skin selection persisted there in headless runs).
