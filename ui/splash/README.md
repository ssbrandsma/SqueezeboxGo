# Splash — 640x480 boot image + DRM painter

- `splash_640x480.png` — the image (committed; 640x480 8-bit RGB).
  Deterministic output of `make_splash.py` (stdlib-only: gradient +
  5x7 headline `SQUEEZEBOX` / `RG35XX H` / `SQUEEZEPLAY 8.0`).
- `make_splash.py` — generator. Re-run must be byte-identical
  (`cmp` in validation).
- `pngmini.{c,h}` — dependency-free (libc+zlib) PNG decoder for exactly
  our asset class (8-bit RGB/RGBA, non-interlaced, all filters).
- `blit.{c,h}` — center/composite the decoded image onto XRGB8888.
- `drm_splash.c` — painter using raw DRM UAPI ioctls (dumb buffer +
  `SETCRTC`); needs no libdrm, holds master until SIGTERM.
- `init-splash.sh` — boot glue (`show`/`stop`, backend ladder).
- `SERVICE_HOOKS.md` — install paths + unit snippets for Agent 1.

## Host validation

```sh
python3 make_splash.py /tmp/regen.png && cmp splash_640x480.png /tmp/regen.png
file splash_640x480.png   # PNG image data, 640 x 480, 8-bit/color RGB
gcc -std=c99 -Wall -Wextra -O2 -o /tmp/test_splash test_splash.c \
    pngmini.c blit.c -lz && /tmp/test_splash splash_640x480.png
gcc -std=c99 -Wall -Wextra -O2 -o /tmp/drm_splash drm_splash.c \
    pngmini.c blit.c -lz   # must build warning-free
sh -n init-splash.sh
```

Live DRM paint needs `/dev/dri/card0` + panel (WP2 hardware item); the
decode/blit/center/composite path is fully covered on host.
