# Stock framebuffer route: SDL 1.2.15 fbcon (vendor 4.9 kernel track)

Scope: running SqueezePlay/Jive on the **stock** RG35XX H card (Ubuntu 22.04
Jammy ARM64, vendor kernel 4.9.170): `/dev/fb0` exists, `/dev/dri` does NOT
([hardware inventory](../docs/hardware.md#verified-graphics-stock-kernel)).
This is the **B2 stock track** — analysis + build recipe only. It changes
nothing in the shipped mainline target stack.

Hard rules (unchanged): no device access from here — every probe below is a
user-run read-only command. Never overwrite the working stock SD; all
deployment is user-executed, reversible, second-card-safe.

## 1. Why fbcon, and why our shipped stack cannot do it

Our mainline UI decision is SDL 1.2 API via sdl12-compat on SDL2/KMSDRM
(`ui/README.md` §1). That chain needs all of:

- `/dev/dri/card0` + a modern DRM/KMS driver (our OOT panel stack),
- SDL2 ≥ 2.30 built with `kmsdrm` video + `libinput` + `xkbcommon`,
- sdl12-compat's `libSDL-1.2.so.0` shadowing the build-ABI libSDL at image
  assembly time (`build/image/stage-payload.sh` step 3: it **deletes** the
  build-ABI `libSDL-1.2.so.0*` and installs compat + SDL2 2.32.10).

On the stock 4.9 BSP kernel there is no `/dev/dri`, no KMS, no libinput
console path — `SDL_VIDEODRIVER=kmsdrm` has nothing to open. The only
kernel graphics interface is the legacy framebuffer `/dev/fb0`
(`mali_kbase` is present but the vendor stack is legacy fb).

Therefore the stock route is **real SDL 1.2.15 with its `fbcon` video
driver**, opening `/dev/fb0` directly. No SDL2, no compat shim, no DRM.

## 2. What our current SDL 1.2.15 build lacks

Reference: `squeezeplay/configuration/Makefile.linux-aarch64:180-184`.

Our tree builds SDL-1.2.15 as **headers + link ABI only**:

```sh
cd SDL-1.2.15; ./configure $(CONFIGURE_CROSS) --prefix=${PREFIX} ...
  --enable-audio=no ... --enable-alsa=no ...
  --enable-video-x11=no --enable-video-opengl=no --enable-video-directfb=no ...
```

- The comment in the Makefile says it explicitly: *"Dummy/fbcon video stay
  enabled so configure always finds >=1 video driver."* fbcon is left at
  configure default purely so the link succeeds; the resulting libSDL is
  **never shipped** — `stage-payload.sh` removes it and installs
  sdl12-compat instead.
- sdl12-compat 1.2.78 (`ui/vendor/sdl12-compat.pin`) implements the SDL 1.2
  API **on top of SDL2**; SDL2's only X-less driver is `kmsdrm`, which
  needs `/dev/dri`. There is no fbdev backend in SDL2 modern releases and
  none in the compat shim.
- Net: nothing we ship today can open `/dev/fb0`. The stock track needs a
  **separate, real SDL-1.2.15 fbcon build** (recipe below). It must NOT
  replace the mainline SDL stack — different card, different prefix
  (e.g. `/opt/squeezeplay-stock/`), selected at launch time.

## 3. Exact SDL-1.2.15 configure recipe for fbcon

Build host = any aarch64 cross setup already used for this project
(contract flags `-march=armv8-a+crc -mtune=cortex-a53`; see
`ui/BRINGUP.md` appendix A). Source = the same SDL-1.2.15 tree the core
build already uses (Agent 2 owns the tarball/patches; no new pin here).

```sh
# Unpack SDL-1.2.15 to $SRC (same source Agent 2 builds), then:
cd "$SRC"
./configure --host=aarch64-linux-gnu --prefix=/opt/squeezeplay-stock \
  --enable-shared --disable-static \
  --enable-video --enable-video-fbcon=yes --enable-video-dummy=yes \
  --enable-video-x11=no --enable-video-directfb=no --enable-video-opengl=no \
  --enable-video-svga=no --enable-video-aalib=no --enable-video-caca=no \
  --enable-events --enable-threads --enable-timers --enable-file \
  --enable-loadso --enable-clock_gettime \
  --enable-joystick=no --enable-cdrom=no \
  --enable-audio=no --enable-oss=no --enable-alsa=no --enable-esd=no \
  --enable-arts=no --enable-pulseaudio=no
make && make DESTDIR="$STAGE" install
```

Notes:

- `--enable-video-fbcon=yes` forces the fbcon driver on (it is the default
  on Linux when fb headers are present, but force it so a quiet
  auto-disable cannot slip through). Verify in configure output:
  `Video drivers: ... fbcon ...`, and in the generated
  `include/SDL_config.h`: `#define SDL_VIDEO_DRIVER_FBCON 1`.
- Audio stays disabled deliberately: Jive audio goes through its own
  `jive_alsa` ALSA backend (`audio/ALSA_PATH.md`), never through SDL —
  same as the mainline build. SDL joystick stays off: input comes from
  `evdev2jive` (see `ui/stock-input.md`).
- Runtime environment on stock (launcher sets these, cf. mainline
  `SDL_VIDEODRIVER=kmsdrm` in `platform/rg35xx-h/services/squeezeplay.sh`):

  ```sh
  export SDL_VIDEODRIVER=fbcon
  export SDL_FBDEV=/dev/fb0
  export FRAMEBUFFER=/dev/fb0
  ```

- fbcon needs read/write on `/dev/fb0` and a text console VT to be the
  active terminal (stock Ubuntu without X normally satisfies this on the
  physical console). If `SDL_SetVideoMode` fails with "No available video
  device", check `ls -l /dev/fb0` permissions and that no vendor UI holds
  the console.
- Smoke test: reuse `ui/tests/sdl_smoke.c` unchanged (it already calls
  `SDL_SetVideoMode(640,480,16)`), built against the fbcon libSDL and run
  with the env above. Expected: `video driver: fbcon`, `ALL PASS`.
  (Do NOT run it on the stock card until the fb geometry probes in §5 are
  understood — see the virtual-size warning.)

## 4. Detecting vendor SDL libraries already on the device

Before building anything, check whether the stock image already ships a
usable SDL (vendor launcher may bundle one). Run on the device (UART root
shell), all read-only:

```sh
# 4a. Dynamic linker view
ldconfig -p | grep -i sdl || echo "no SDL in ldconfig cache"
# 4b. Debian package view (stock is Ubuntu Jammy)
dpkg -l | grep -i sdl || echo "no SDL dpkg packages"
# 4c. Well-known library paths
ls -l /usr/lib/aarch64-linux-gnu/libSDL* /usr/lib/libSDL* \
      /usr/local/lib/libSDL* 2>/dev/null || echo "no SDL in system libdirs"
# 4d. Vendor trees (stock layout: appfs @ /mnt/vendor, UDISK @ /mnt/data)
ls /mnt/vendor /mnt/data 2>/dev/null
find /mnt/vendor /mnt/data /opt /usr/local -name 'libSDL*' 2>/dev/null
# 4e. Whole-root fallback (slow on eMMC/SD; run only if 4a-4d found nothing)
find / -xdev -name 'libSDL*' 2>/dev/null
# 4f. What does the vendor launcher link against?
ps aux | head -30                      # identify the launcher process + path
ldd <vendor-launcher-binary> 2>/dev/null | grep -i sdl
strings -a <vendor-launcher-binary> | grep -i -m5 'SDL_'
```

Record: library path, `libSDL-1.2.so.0` vs `libSDL2`, whether it is
system dpkg-managed (`/usr/lib/...`) or vendor-bundled (`/mnt/vendor/...`).
A vendor-bundled SDL1.2 with fbcon would be the fastest stock path
(`LD_LIBRARY_PATH` + `SDL_VIDEODRIVER=fbcon`); a vendor SDL2 is useless
without `/dev/dri` unless it carries a vendor fbdev backend (check
`strings libSDL2*.so | grep -i -m10 'video.*driver\|kmsdrm\|fbdev'`).

## 5. fbset / vinfo probes: 1280x1024 virtual vs 640x480 LCD

Verified fact: `virtual_size` reports **1280x1024** while the physical LCD
is **640x480** (`docs/hardware.md`). Do NOT assume orientation, stride, or
pixel format. Candidate explanations (all seen on Allwinner BSP fb):

1. Double-height virtual buffer (pan/double-buffering, `yres_virtual =
   2*yres` with different numbers here — 1024 ≠ 2*480, so not plain 2x);
2. A rotated/shadow buffer (e.g. 1024x1280 portrait staging vs 640x480
   panel, or a fixed 1280x1024 BSP default mode scaled by the TCON);
3. Stride/pitch padding (`line_length` > `xres * bpp/8`).

Probes (all read-only; run exactly these, in order):

```sh
# 5a. Existence + driver identity
ls -l /dev/fb* ; ls /dev/dri 2>&1 || echo "no /dev/dri (expected on stock)"
cat /proc/fb
cat /sys/class/graphics/fb0/name
# 5b. Canonical mode line (needs fbset; if missing, use 5d instead)
fbset -i -fb /dev/fb0
fbset -s -fb /dev/fb0
# 5c. sysfs ground truth (always present)
for f in virtual_size bits_per_pixel stride modes mode pan name \
         rotate state blank; do
  printf '%s: ' "$f"; cat /sys/class/graphics/fb0/$f 2>&1 | head -5
done
cat /sys/class/graphics/fb0/modes
# 5d. fbset fallback: raw vinfo/finfo via read-only ioctls (python3)
python3 - <<'EOF'
import fcntl, struct
fb = open('/dev/fb0', 'rb')
v = fcntl.ioctl(fb, 0x4600, b'\0'*160)          # FBIOGET_VSCREENINFO
f = struct.unpack('<40I', v)
print('xres=%d yres=%d xres_virtual=%d yres_virtual=%d '
      'xoffset=%d yoffset=%d bpp=%d grayscale=%d'
      % (f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7]))
print('red    offset=%d len=%d' % (f[8],f[9]))
print('green  offset=%d len=%d' % (f[11],f[12]))
print('blue   offset=%d len=%d' % (f[14],f[15]))
print('transp offset=%d len=%d' % (f[17],f[18]))
print('nonstd=%d activate=%d w_mm=%d h_mm=%d pixclock=%d '
      'margins L/R/U/L=%d/%d/%d/%d sync=%d vmode=%d rotate=%d'
      % (f[20],f[21],f[23],f[22],f[25],f[26],f[27],f[28],f[29],f[32],f[33],f[34]))
fi = fcntl.ioctl(fb, 0x4602, b'\0'*128)         # FBIOGET_FSCREENINFO
id_, smem, rest = struct.unpack('<16sQ8I', fi[:56])
print('id=%s smem_len=%d type=%d visual=%d line_length=%d'
      % (id_.split(b'\0')[0].decode(), rest[0], rest[1], rest[3], rest[7]))
EOF
```

What to record in the evidence doc: `xres/yres`, `xres_virtual/
yres_virtual`, `xoffset/yoffset`, `bpp`, RGBA offsets/lengths (→
RGB565 vs XRGB8888 vs BGR), `line_length` (→ stride), `visual` (2 =
`FB_VISUAL_TRUECOLOR`, 3 = `FB_VISUAL_PSEUDOCOLOR`), `rotate`, and whether
`fbset`/sysfs agree. Decision rule:

- If `xres=640 yres=480` with a larger virtual buffer: SDL fbcon can
  `SDL_SetVideoMode(640,480,16)` directly; virtual extra is pan space.
- If `xres/yres` itself is 1280x1024 (or other non-640x480): the TCON is
  scaling; try the native `xres/yres` first in the smoke test, note the
  on-panel result (user observes: full-screen? cropped? rotated?), and do
  NOT hardcode 640x480 for the stock track until seen.
- If `rotate != 0` or RGB offsets are BGR-ordered: record it — the stock
  skin/slider path must compensate, and the smoke fill color will confirm.

Optional (NOT part of automated probing — needs eyes on the panel): after
recording the above, run the fbcon `sdl_smoke` and report panel result.

## 6. Open questions for the bundle / probe agent

1. `fbset` present on stock? (informs whether stock-probe.sh needs the
   python fallback.)
2. Vendor SDL present? (path + version + fbcon support.)
3. fb geometry answer from §5 (blocks any stock video mode choice).
