#!/usr/bin/env python3
"""make-icon.py — generate the SqueezeboxGo App Center icon (160x120 RGBA PNG).

Stdlib-only (struct + zlib); deterministic byte-for-byte output so the
icon is reproducible at pack time and never committed to git (repo policy:
git stays text-only; pack.sh regenerates this PNG into the ZIP).

Usage:
    python3 make-icon.py [-o SqueezeboxGo.png]

Design (readable at App Center thumbnail size):
  dark rounded backdrop -> orange handheld-device slab with a glowing
  display showing EQ bars (audio motif) + speaker arcs + play triangle.
  High-contrast silhouette, no fine text (illegible at 160x120).
"""
import struct
import sys
import zlib

W, H = 160, 120

# Palette
BG_TOP = (24, 28, 40, 255)       # deep navy
BG_BOT = (10, 12, 20, 255)       # near black
SLAB = (242, 124, 22, 255)       # squeezebox orange
SLAB_DK = (176, 82, 10, 255)     # slab shadow edge
SCREEN = (16, 22, 34, 255)       # display glass
SCREEN_GLOW = (64, 200, 255, 255)  # display glow accent
BAR = (120, 255, 140, 255)       # EQ bars (green)
BAR_HOT = (255, 214, 64, 255)    # hottest EQ bar (amber)
WAVE = (235, 240, 250, 255)      # speaker arcs (white)
PLAY = (255, 255, 255, 255)      # play triangle
SHADOW = (0, 0, 0, 110)          # drop shadow (alpha-blended)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = bytearray(w * h * 4)

    def blend(self, x, y, c):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        i = (y * self.w + x) * 4
        sa = c[3] / 255.0
        if sa >= 1.0:
            self.px[i:i + 4] = bytes(c)
            return
        if sa <= 0.0:
            return
        d = self.px[i:i + 4]
        self.px[i] = int(c[0] * sa + d[0] * (1 - sa))
        self.px[i + 1] = int(c[1] * sa + d[1] * (1 - sa))
        self.px[i + 2] = int(c[2] * sa + d[2] * (1 - sa))
        self.px[i + 3] = 255

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.blend(x, y, c)

    def rrect(self, x0, y0, x1, y1, r, c):
        # filled rounded rect via distance-tested corners
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                cx = min(max(x, x0 + r), x1 - r - 1)
                cy = min(max(y, y0 + r), y1 - r - 1)
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r * r:
                    self.blend(x, y, c)

    def disc(self, cx, cy, rad, c, fill=True, thick=2):
        r2o, r2i = rad * rad, (rad - thick) * (rad - thick)
        for y in range(cy - rad - 1, cy + rad + 2):
            for x in range(cx - rad - 1, cx + rad + 2):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if fill:
                    if d2 <= r2o:
                        self.blend(x, y, c)
                elif r2i <= d2 <= r2o:
                    self.blend(x, y, c)

    def arc(self, cx, cy, rad, c, xside=1, thick=3):
        # quarter-ish arc open toward -xside (speaker wave)
        r2o, r2i = rad * rad, (rad - thick) * (rad - thick)
        for y in range(cy - rad - 1, cy + rad + 2):
            for x in range(cx - rad - 1, cx + rad + 2):
                if (x - cx) * xside < 0:
                    continue
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if r2i <= d2 <= r2o:
                    self.blend(x, y, c)

    def tri(self, x0, y0, x1, y1, x2, y2, c):
        # filled triangle via barycentric sign test
        def sign(ax, ay, bx, by, cx, cy):
            return (ax - cx) * (by - cy) - (bx - cx) * (ay - cy)
        xs = (min(x0, x1, x2), max(x0, x1, x2))
        ys = (min(y0, y1, y2), max(y0, y1, y2))
        for y in range(max(0, ys[0]), min(self.h, ys[1] + 1)):
            for x in range(max(0, xs[0]), min(self.w, xs[1] + 1)):
                b1 = sign(x, y, x0, y0, x1, y1) < 0
                b2 = sign(x, y, x1, y1, x2, y2) < 0
                b3 = sign(x, y, x2, y2, x0, y0) < 0
                if b1 == b2 == b3:
                    self.blend(x, y, c)


def draw():
    cv = Canvas(W, H)
    # backdrop: vertical gradient + vignette corners
    for y in range(H):
        cv.rect(0, y, W, y + 1, lerp(BG_TOP, BG_BOT, y / (H - 1)))
    for (vx, vy) in ((0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)):
        cv.disc(vx, vy, 46, (0, 0, 0, 70))

    # drop shadow + device slab (portable music player, left 2/3)
    sx0, sy0, sx1, sy1 = 18, 14, 108, 106
    cv.rrect(sx0 + 4, sy0 + 5, sx1 + 4, sy1 + 5, 12, SHADOW)
    cv.rrect(sx0, sy0, sx1, sy1, 12, SLAB)
    # slab edge shading: dark bottom strip + top highlight line
    cv.rrect(sx0, sy1 - 12, sx1, sy1, 6, (0, 0, 0, 60))
    cv.rect(sx0 + 12, sy0 + 2, sx1 - 12, sy0 + 4, (255, 255, 255, 70))

    # display glass
    dx0, dy0, dx1, dy1 = sx0 + 9, sy0 + 10, sx1 - 9, sy0 + 62
    cv.rrect(dx0, dy0, dx1, dy1, 5, SCREEN)
    cv.rect(dx0 + 4, dy0 + 2, dx1 - 4, dy0 + 4, (255, 255, 255, 40))
    # display glow dot (power LED)
    cv.disc(dx1 - 8, dy0 + 8, 2, SCREEN_GLOW)

    # EQ bars inside display (audio motif)
    bars = (14, 26, 20, 34, 24, 38, 28, 16)
    bw, gap = 5, 3
    base = dy1 - 7
    x = dx0 + 7
    for i, bh in enumerate(bars):
        c = BAR_HOT if i == 5 else BAR
        cv.rect(x, base - bh, x + bw, base, c)
        cv.rect(x, base - bh, x + bw, base - bh + 2, (255, 255, 255, 120))
        x += bw + gap

    # play triangle (media motif) centered under display
    cv.tri(52, 76, 52, 94, 68, 85, PLAY)
    # control dots row (player buttons)
    for dx in (30, 42, 84, 96):
        cv.disc(dx, 85, 4, SLAB_DK)
        cv.disc(dx, 85, 2, (255, 255, 255, 160))

    # speaker + waves on the right third
    cv.disc(128, 60, 13, (30, 34, 48, 255))
    cv.disc(128, 60, 13, WAVE, fill=False, thick=3)
    cv.disc(128, 60, 6, WAVE)
    cv.disc(128, 60, 2, (30, 34, 48, 255))
    cv.arc(128, 60, 22, WAVE, xside=1, thick=3)
    cv.arc(128, 60, 30, (235, 240, 250, 160), xside=1, thick=3)
    cv.arc(128, 60, 22, WAVE, xside=-1, thick=3)
    return cv


def write_png(cv, path):
    def chunk(typ, data):
        out = struct.pack(">I", len(data)) + typ + data
        return out + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(cv.h):
        raw.append(0)  # filter 0 (None) — deterministic
        raw += cv.px[y * cv.w * 4:(y + 1) * cv.w * 4]
    comp = zlib.compress(bytes(raw), 9)
    ihdr = struct.pack(">IIBBBBB", cv.w, cv.h, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", comp) + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


def main(argv):
    out = "SqueezeboxGo.png"
    if len(argv) == 3 and argv[1] == "-o":
        out = argv[2]
    elif len(argv) != 1:
        sys.stderr.write("usage: make-icon.py [-o OUT.png]\n")
        return 2
    n = write_png(draw(), out)
    print("wrote %s (%d bytes, %dx%d RGBA)" % (out, n, W, H))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
