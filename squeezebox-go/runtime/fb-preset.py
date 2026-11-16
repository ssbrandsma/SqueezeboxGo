#!/usr/bin/env python3
"""fb-preset.py — set + verify one framebuffer mode (SqueezeboxGo).

Two modes:
  fb-preset.py [WxHxBPP]          PUT the mode now, verify, exit 0/1.
  fb-preset.py --watch-clobber    poll for SDL's 512x384 mode clobber
      (Jive's first FBIOPUT leaves vinfo 512x384x32 while painting a
      640x480x32 frame — proven live 2026-11-16) and re-assert the
      target mode the moment it appears; exit 0 after fixing, 1 on
      timeout. Safe to run while Jive exits: only reacts to 512x384.

Same ioctl sequence as stock/bundle/display-trial.py --preset
(read current var, replace geometry, PUT, read back, compare).
"""
import fcntl
import struct
import sys
import time

FBIOGET_VSCREENINFO = 0x4600
FBIOPUT_VSCREENINFO = 0x4601
VAR_FMT = "<40I"
VAR_NAMES = ("xres,yres,xres_virtual,yres_virtual,xoffset,yoffset,"
             "bits_per_pixel,grayscale,"
             "red.offset,red.length,red.msb_right,"
             "green.offset,green.length,green.msb_right,"
             "blue.offset,blue.length,blue.msb_right,"
             "transp.offset,transp.length,transp.msb_right,"
             "nonstd,activate,height,width,accel_flags,pixclock,"
             "left_margin,right_margin,upper_margin,lower_margin,"
             "hsync_len,vsync_len,sync,vmode,rotate,colorspace,"
             "reserved0,reserved1,reserved2,reserved3").split(",")
assert len(VAR_NAMES) == 40

TARGET = (640, 480, 32)
CLOBBER = (512, 384)


def get_var(fb):
    with open(fb, "r+b") as f:
        buf = fcntl.ioctl(f.fileno(), FBIOGET_VSCREENINFO,
                          bytes(160))
    return dict(zip(VAR_NAMES, struct.unpack(VAR_FMT, buf)))


def put_mode(fb, w, h, bpp):
    v = get_var(fb)
    v.update(xres=w, yres=h, bits_per_pixel=bpp,
             xres_virtual=w, yres_virtual=h,
             xoffset=0, yoffset=0, activate=0)
    with open(fb, "r+b") as f:
        fcntl.ioctl(f.fileno(), FBIOPUT_VSCREENINFO,
                    struct.pack(VAR_FMT, *[v[k] for k in VAR_NAMES]))
    cur = get_var(fb)
    ok = (cur["xres"], cur["yres"],
          cur["bits_per_pixel"]) == (w, h, bpp)
    print("preset %dx%dx%d: active %dx%d/%d %s" % (
        w, h, bpp, cur["xres"], cur["yres"],
        cur["bits_per_pixel"], "OK" if ok else "MISMATCH"))
    return ok


def watch_clobber(fb, timeout=25):
    end = time.time() + timeout
    while time.time() < end:
        try:
            v = get_var(fb)
        except OSError as e:
            print("watch: read failed: %r" % e)
            return False
        if (v["xres"], v["yres"]) == CLOBBER:
            print("watch: clobber %dx%d seen, re-asserting" % CLOBBER)
            return put_mode(fb, *TARGET)
        if (v["xres"], v["yres"], v["bits_per_pixel"]) == TARGET:
            print("watch: target already active")
            return True
        time.sleep(0.5)
    print("watch: timeout, no clobber seen")
    return False


def main(argv):
    fb = "/dev/fb0"
    args = [a for a in argv if not a.startswith("--fb=")]
    for a in argv:
        if a.startswith("--fb="):
            fb = a[5:]
    if "--watch-clobber" in args:
        try:
            return 0 if watch_clobber(fb) else 1
        except OSError as e:
            print("watch FAILED: %r" % e, file=sys.stderr)
            return 1
    spec = "%dx%dx%d" % TARGET
    for a in args:
        if not a.startswith("--"):
            spec = a
    try:
        w, h, b = (int(x) for x in
                   spec.lower().replace("x", " ").split())
    except ValueError:
        print("bad mode spec (want WxHxBPP): %s" % spec,
              file=sys.stderr)
        return 2
    try:
        return 0 if put_mode(fb, w, h, b) else 1
    except OSError as e:
        print("preset %s FAILED: %r" % (spec, e), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
