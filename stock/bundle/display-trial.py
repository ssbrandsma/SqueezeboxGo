#!/usr/bin/env python3
"""display-trial.py — numbered framebuffer visibility carousel (stock PoC).

Shows numbered full-screen test patterns so a human watcher can report
WHICH geometry/format the LCD actually displays. Each attempt sets a
framebuffer mode, draws a big seven-segment number plus orientation
markers, holds it, and logs the before/after mode. Stock mode is
restored (and verified) at the end.

Attempts (edit ATTEMPTS to change the matrix):
  1: current mode untouched (baseline — is fb0 even scanned out?)
  2: 640x480x16
  3: 1280x1024x16, picture drawn only in top-left 640x480 (crop test)
  4: 640x480x32 (XRGB8888)
  5: 640x480x16 with virtual 1280x1024 (xres != vxres)
  6: 512x384x32 (the sticky mode Jive fell into — informative)

Usage (on device, as root):
    python3 display-trial.py [--fb /dev/fb0] [--hold 8] [--rounds 3]
Host verification (no fb needed):
    python3 display-trial.py --save-png /tmp/trial-pngs

A mode-set failure never aborts the carousel: the attempt is drawn at
whatever geometry resulted, and the mismatch is logged. Requires root
only for FBIOPUT/mmap on a real fb; --save-png runs anywhere.
"""
import argparse
import fcntl
import mmap
import os
import struct
import subprocess
import sys
import time
import zlib

FBIOGET_VSCREENINFO = 0x4600
FBIOPUT_VSCREENINFO = 0x4601
FBIOGET_FSCREENINFO = 0x4602

# struct fb_var_screeninfo: 40 x u32 = 160 bytes, EXACT kernel UAPI order
# (uapi/linux/fb.h). PUT must round-trip every field: packing a short
# struct corrupts timings/margins the driver keeps in the tail.
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

# struct fb_fix_screeninfo (64-bit): id[16], smem_start(Q),
# smem_len/type/type_aux/visual(4I), xpan/ypan/ywrapstep(3H), 2 pad bytes,
# line_length(I @48), ... — we only need smem_len + line_length.
FIX_PREFIX_FMT = "<16sQ4I3H2xI"
FIX_SMEM_LEN_IDX = 2  # index into unpacked tuple below
FIX_LINE_LENGTH_IDX = 9

ATTEMPTS = [
    # (number, xres, yres, bpp, vxres_or_None, note)
    # Attempt 1 RE-ASSERTS stock geometry every round (never "untouched":
    # in rounds 2+ it would inherit attempt 6's mode — observed live).
    (1, None, None, None, None, "stock geometry re-asserted (baseline)"),
    (2, 640, 480, 16, None, "native LCD geometry RGB565"),
    (3, 1280, 1024, 16, None, "stock geometry, picture in top-left 640x480"),
    (4, 640, 480, 32, None, "native geometry XRGB8888"),
    (5, 640, 480, 16, 1280, "640x480 window in 1280 virt (xoffset 0)"),
    (6, 512, 384, 32, None, "Jive sticky mode (informative)"),
]

SEGMENTS = {  # seven-seg: a=top b=tr c=br d=bot e=bl f=tl g=mid
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afedcg", "7": "abc", "8": "abcdefg", "9": "abfgcd",
}


def log(msg, fh):
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), msg)
    print(line, flush=True)
    if fh:
        fh.write(line + "\n")


class Canvas:
    def __init__(self, w, h, bpp):
        assert bpp in (16, 32)
        self.w, self.h, self.bpp = w, h, bpp
        self.px = bytearray(w * h * (bpp // 8))

    def put(self, x, y, r, g, b):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        if self.bpp == 16:
            v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            struct.pack_into("<H", self.px, (y * self.w + x) * 2, v)
        else:
            i = (y * self.w + x) * 4
            self.px[i:i + 4] = bytes((b, g, r, 0))

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.put(x, y, *c)

    def digit(self, ch, cx, cy, h, c):
        w, t = h // 2, max(2, h // 12)
        x0, y0 = cx - w // 2, cy - h // 2
        segs = {
            "a": (x0, y0, x0 + w, y0 + t),
            "b": (x0 + w - t, y0, x0 + w, y0 + h // 2),
            "c": (x0 + w - t, y0 + h // 2, x0 + w, y0 + h),
            "d": (x0, y0 + h - t, x0 + w, y0 + h),
            "e": (x0, y0 + h // 2, x0 + t, y0 + h),
            "f": (x0, y0, x0 + t, y0 + h // 2),
            "g": (x0, y0 + h // 2 - t // 2, x0 + w, y0 + h // 2 + t // 2),
        }
        for s in SEGMENTS[ch]:
            self.rect(*segs[s], c)

    def tri_up(self, cx, y0, half, h, c):
        for i in range(h):
            wrow = int(half * (1 - i / h))
            self.rect(cx - wrow, y0 + i, cx + wrow, y0 + i + 1, c)


def draw_pattern(num, w, h, bpp, region_640=False):
    cv = Canvas(w, h, bpp)
    cv.rect(0, 0, w, h, (10, 12, 24))
    if region_640:
        cv.rect(0, 0, 640, 480, (10, 12, 24))
        cv.rect(0, 0, 640, 3, (255, 255, 255))
        cv.rect(0, 477, 640, 480, (255, 255, 255))
        cv.rect(0, 0, 3, 480, (255, 255, 255))
        cv.rect(637, 0, 640, 480, (255, 255, 255))
        dw, dh, ox = 640, 480, 0
    else:
        b = 3
        cv.rect(0, 0, w, b, (255, 255, 255))
        cv.rect(0, h - b, w, h, (255, 255, 255))
        cv.rect(0, 0, b, h, (255, 255, 255))
        cv.rect(w - b, 0, w, h, (255, 255, 255))
        dw, dh, ox = w, h, 0
    # grid dots every 64 px (stride/offset tell-tale)
    for gy in range(32, dh, 64):
        for gx in range(32, dw, 64):
            cv.rect(ox + gx - 1, gy - 1, ox + gx + 1, gy + 1, (90, 90, 110))
    # color bars along the bottom of the draw area
    bars = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255),
            (255, 255, 0), (0, 255, 255)]
    bw = dw // len(bars)
    for i, c in enumerate(bars):
        cv.rect(ox + i * bw, dh - 40, ox + (i + 1) * bw, dh - 16, c)
    # orientation: amber triangle top-center, magenta square bottom-right
    cv.tri_up(ox + dw // 2, 8, 18, 30, (255, 170, 0))
    cv.rect(ox + dw - 34, dh - 70, ox + dw - 10, dh - 46, (255, 0, 255))
    # the big number
    cv.digit(str(num), ox + dw // 2, dh // 2 - 10, min(150, dh // 3),
             (255, 255, 255))
    return cv


def write_png(path, cv):
    def chunk(typ, data):
        out = struct.pack(">I", len(data)) + typ + data
        return out + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)

    raw = bytearray()
    B = cv.bpp // 8
    for y in range(cv.h):
        raw.append(0)
        row = cv.px[y * cv.w * B:(y + 1) * cv.w * B]
        if cv.bpp == 16:
            out = bytearray()
            for i in range(0, len(row), 2):
                v = struct.unpack_from("<H", row, i)[0]
                out += bytes((((v >> 11) & 31) * 255 // 31,
                               ((v >> 5) & 63) * 255 // 63,
                               (v & 31) * 255 // 31, 255))
            raw += out
        else:
            for i in range(0, len(row), 4):
                b, g, r, _ = row[i:i + 4]
                raw += bytes((r, g, b, 255))
    comp = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", cv.w, cv.h, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                + chunk(b"IDAT", comp) + chunk(b"IEND", b""))


def unpack_var(buf):
    assert len(buf) == 160, "var_screeninfo must be 160 bytes"
    return dict(zip(VAR_NAMES, struct.unpack(VAR_FMT, buf)))


def pack_var(v):
    return struct.pack(VAR_FMT, *[v[k] for k in VAR_NAMES])


def unpack_fix(buf):
    vals = struct.unpack(FIX_PREFIX_FMT, buf[:struct.calcsize(FIX_PREFIX_FMT)])
    return {"smem_len": vals[FIX_SMEM_LEN_IDX],
            "line_length": vals[FIX_LINE_LENGTH_IDX]}


def get_var(fb):
    with open(fb, "r+b") as f:
        buf = fcntl.ioctl(f.fileno(), FBIOGET_VSCREENINFO, bytes(160))
    return unpack_var(buf)


def get_fix(fb):
    with open(fb, "r+b") as f:
        buf = fcntl.ioctl(f.fileno(), FBIOGET_FSCREENINFO, bytes(128))
    return unpack_fix(buf)


def put_var(fb, v):
    with open(fb, "r+b") as f:
        fcntl.ioctl(f.fileno(), FBIOPUT_VSCREENINFO, pack_var(v))


def frontend_alive():
    """True if dmenu.bin is running (it repaints fb constantly)."""
    try:
        r = subprocess.run(["pidof", "dmenu.bin"], capture_output=True)
    except OSError:
        return False
    return r.returncode == 0 and bool(r.stdout.strip())


def restore_stock(fb, orig, saved, fh):
    """Restore stock mode + pixels. Tries the proven geometry-forced PUT
    first (exact shape that succeeded 6/6 on device), then exact
    round-trip. Returns True iff geometry matches afterwards."""
    forced = dict(orig)
    forced.update(xres=orig["xres"], yres=orig["yres"],
                  bits_per_pixel=orig["bits_per_pixel"],
                  xres_virtual=orig["xres"], yres_virtual=orig["yres"],
                  xoffset=0, yoffset=0, activate=0)
    for name, cand in (("geometry-forced", forced), ("exact", orig)):
        try:
            put_var(fb, cand)
        except OSError as e:
            log("restore PUT %s failed: %r" % (name, e), fh)
            continue
        cur = get_var(fb)
        if (cur["xres"], cur["yres"], cur["bits_per_pixel"]) == (
                orig["xres"], orig["yres"], orig["bits_per_pixel"]):
            log("restore PUT %s ok" % name, fh)
            break
    else:
        return False
    fix = get_fix(fb)
    with open(fb, "r+b") as f:
        mm = mmap.mmap(f.fileno(), fix["smem_len"])
        mm[:len(saved)] = saved
        try:
            mm.flush()
        except OSError:
            pass
        mm.close()
    return True


def blit(fb, cv, xres, yres, stride, smem_len):
    nbytes = min(yres * stride, smem_len)
    with open(fb, "r+b") as f:
        mm = mmap.mmap(f.fileno(), smem_len)
        src_B = cv.bpp // 8
        roww = min(cv.w * src_B, stride)
        for y in range(min(cv.h, yres)):
            s = cv.px[y * cv.w * src_B:y * cv.w * src_B + roww]
            mm[y * stride:y * stride + roww] = s
        try:
            mm.flush()
        except OSError:
            pass  # fb mappings reject msync (EINVAL); writes still land
        mm.close()


def main(argv):
    ap = argparse.ArgumentParser(description="numbered fb visibility carousel")
    ap.add_argument("--fb", default="/dev/fb0")
    ap.add_argument("--hold", type=int, default=8)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--log", default="/tmp/display-trial.log")
    ap.add_argument("--save-png", default=None,
                    help="render attempts to PNGs instead of fb (host check)")
    ap.add_argument("--force", action="store_true",
                    help="run even with dmenu alive (patterns get overpainted)")
    ap.add_argument("--preset", default=None, metavar="WxHxBPP",
                    help="PUT one mode (e.g. 640x480x32), verify, exit; "
                    "no drawing (for pre-setting fb before Jive)")
    ap.add_argument("--restore-stock", action="store_true",
                    help="PUT 1280x1024x16 back, verify, exit")
    args = ap.parse_args(argv)

    if args.preset or args.restore_stock:
        spec = "1280x1024x16" if args.restore_stock else args.preset
        try:
            w, h, b = (int(x) for x in
                       spec.lower().replace("x", " ").split())
        except ValueError:
            print("bad mode spec (want WxHxBPP): %s" % spec,
                  file=sys.stderr)
            return 2
        try:
            orig = get_var(args.fb)
            v = dict(orig)
            v.update(xres=w, yres=h, bits_per_pixel=b,
                     xres_virtual=w, yres_virtual=h,
                     xoffset=0, yoffset=0, activate=0)
            put_var(args.fb, v)
            cur = get_var(args.fb)
        except OSError as e:
            print("preset %s FAILED: %r" % (spec, e), file=sys.stderr)
            return 1
        ok = (cur["xres"], cur["yres"], cur["bits_per_pixel"]) == (w, h, b)
        print("preset %s: active %dx%d/%d %s" % (
            spec, cur["xres"], cur["yres"], cur["bits_per_pixel"],
            "OK" if ok else "MISMATCH"))
        return 0 if ok else 1

    if args.save_png:
        os.makedirs(args.save_png, exist_ok=True)
        for num, x, y, bpp, vx, note in ATTEMPTS:
            w, h, b = x or 1280, y or 1024, bpp or 16
            cv = draw_pattern(num, w, h, b, region_640=(num == 3))
            p = os.path.join(args.save_png, "attempt-%d.png" % num)
            write_png(p, cv)
            print("wrote %s (%dx%dx%d) %s" % (p, w, h, b, note))
        return 0

    if not args.force and frontend_alive():
        print("REFUSING: dmenu.bin is running and would overpaint every "
              "pattern within milliseconds. Stop the frontend first "
              "(systemctl stop launcher.service) or pass --force.",
              file=sys.stderr)
        return 3

    fh = open(args.log, "w")
    try:
        orig = get_var(args.fb)
        fix0 = get_fix(args.fb)
        log("stock vinfo: %dx%d/%dbpp virt=%dx%d off=%d,%d "
            "line_length=%d smem=%d rotate=%s" % (
                orig["xres"], orig["yres"], orig["bits_per_pixel"],
                orig["xres_virtual"], orig["yres_virtual"],
                orig["xoffset"], orig["yoffset"],
                fix0["line_length"], fix0["smem_len"], orig["rotate"]), fh)
        # save current pixels for restore
        with open(args.fb, "r+b") as f:
            mm0 = mmap.mmap(f.fileno(), fix0["smem_len"])
            saved = bytes(mm0[:])
            mm0.close()
        log("saved %d framebuffer bytes for restore" % len(saved), fh)

        # Pre-render every attempt up front: pure-python painting of a
        # full 1280x1024 frame takes ~9 s; observers must see instant
        # flips. Attempt 1 uses the LIVE stock geometry (not assumed).
        rendered = {}
        for num, x, y, bpp, vx, note in ATTEMPTS:
            if x is None:
                w, h, b = orig["xres"], orig["yres"], \
                    orig["bits_per_pixel"]
            else:
                w, h, b = x, y, bpp
            rendered[num] = draw_pattern(num, w, h, b,
                                         region_640=(num == 3 and w > 640))
        print("pre-rendered %d patterns" % len(rendered), flush=True)
        log("pre-rendered %d patterns" % len(rendered), fh)

        for rnd in range(1, args.rounds + 1):
            for num, x, y, bpp, vx, note in ATTEMPTS:
                log("--- round %d/%d attempt %d: %s ---" % (
                    rnd, args.rounds, num, note), fh)
                v = dict(orig)
                if x is None:
                    # attempt 1: re-assert stock (never inherit last mode)
                    v.update(xres=orig["xres"], yres=orig["yres"],
                             bits_per_pixel=orig["bits_per_pixel"],
                             xres_virtual=orig["xres"],
                             yres_virtual=orig["yres"],
                             xoffset=0, yoffset=0, activate=0)
                else:
                    v.update(xres=x, yres=y, bits_per_pixel=bpp,
                             xres_virtual=vx or x, yres_virtual=y,
                             xoffset=0, yoffset=0, activate=0)
                try:
                    put_var(args.fb, v)
                except OSError as e:
                    log("PUT FAILED (%s); drawing at resulting mode" % e,
                        fh)
                cur = get_var(args.fb)
                fix = get_fix(args.fb)
                log("active: %dx%d/%dbpp virt=%dx%d off=%d,%d "
                    "line_length=%d smem=%d" % (
                        cur["xres"], cur["yres"], cur["bits_per_pixel"],
                        cur["xres_virtual"], cur["yres_virtual"],
                        cur["xoffset"], cur["yoffset"],
                        fix["line_length"], fix["smem_len"]), fh)
                key = (cur["xres"], cur["yres"], cur["bits_per_pixel"])
                cv = rendered.get(num)
                if (cv.w, cv.h, cv.bpp) != (key[0], key[1], key[2]):
                    log("mode differs from plan; redrawing pattern #%d "
                        "live (slow path)" % num, fh)
                    cv = draw_pattern(num, key[0], key[1], key[2],
                                      region_640=(num == 3 and key[0] > 640))
                blit(args.fb, cv, cur["xres"], cur["yres"],
                     fix["line_length"], fix["smem_len"])
                log("showing #%d for %ds — OBSERVE LCD NOW" % (num, args.hold),
                    fh)
                time.sleep(args.hold)
    finally:
        try:
            ok = restore_stock(args.fb, orig, saved, fh)
            log("RESTORE %s" % ("OK" if ok else
                                "FAILED — reboot restores stock"), fh)
        except Exception as e:  # noqa: BLE001 — restore must not raise
            log("RESTORE FAILED: %r — reboot restores stock" % e, fh)
        fh.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
