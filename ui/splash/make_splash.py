#!/usr/bin/env python3
"""make_splash.py — generate the 640x480 Squeezebox boot splash (stdlib only).

Deterministic: same bytes on every run (fixed palette, zlib level, no time).
Usage: make_splash.py [out.png]   (default: splash_640x480.png next to script)
"""
import os
import struct
import sys
import zlib

W, H = 640, 480

# palette
TOP = (11, 18, 32)        # gradient top
BOT = (19, 30, 51)        # gradient bottom
WHITE = (235, 238, 245)
TEAL = (46, 196, 182)
AMBER = (245, 166, 35)
GRAY = (120, 130, 150)

# 5x7 column-major font, LSB = top pixel (classic public-domain set)
F = {
 'A': (0x7E,0x11,0x11,0x11,0x7E), 'B': (0x7F,0x49,0x49,0x49,0x36),
 'C': (0x3E,0x41,0x41,0x41,0x22), 'D': (0x7F,0x41,0x41,0x22,0x1C),
 'E': (0x7F,0x49,0x49,0x49,0x41), 'F': (0x7F,0x48,0x48,0x48,0x40),
 'G': (0x3E,0x41,0x49,0x49,0x7A), 'H': (0x7F,0x08,0x08,0x08,0x7F),
 'I': (0x00,0x41,0x7F,0x41,0x00), 'J': (0x20,0x40,0x41,0x3F,0x01),
 'K': (0x7F,0x08,0x14,0x22,0x41), 'L': (0x7F,0x40,0x40,0x40,0x40),
 'M': (0x7F,0x02,0x0C,0x02,0x7F), 'N': (0x7F,0x04,0x08,0x10,0x7F),
 'O': (0x3E,0x41,0x41,0x41,0x3E), 'P': (0x7F,0x09,0x09,0x09,0x06),
 'Q': (0x3E,0x41,0x51,0x21,0x5E), 'R': (0x7F,0x09,0x19,0x29,0x46),
 'S': (0x46,0x49,0x49,0x49,0x31), 'T': (0x01,0x01,0x7F,0x01,0x01),
 'U': (0x7F,0x40,0x40,0x40,0x7F), 'V': (0x7F,0x20,0x10,0x20,0x7F),
 'W': (0x7F,0x20,0x18,0x20,0x7F), 'X': (0x63,0x14,0x08,0x14,0x63),
 'Y': (0x07,0x08,0x70,0x08,0x07), 'Z': (0x61,0x51,0x49,0x45,0x43),
 '0': (0x3E,0x51,0x49,0x45,0x3E), '1': (0x00,0x42,0x7F,0x40,0x00),
 '2': (0x42,0x61,0x51,0x49,0x46), '3': (0x21,0x41,0x45,0x4B,0x31),
 '4': (0x18,0x14,0x12,0x7F,0x10), '5': (0x27,0x45,0x45,0x45,0x39),
 '6': (0x3C,0x4A,0x49,0x49,0x30), '7': (0x01,0x71,0x09,0x05,0x03),
 '8': (0x36,0x49,0x49,0x49,0x36), '9': (0x06,0x49,0x49,0x29,0x1E),
 ' ': (0x00,0x00,0x00,0x00,0x00), '-': (0x08,0x08,0x08,0x08,0x08),
 '.': (0x00,0x60,0x60,0x00,0x00),
}


def text_w(s, sc):
    return len(s) * 6 * sc - sc


def draw_text(px, s, x, y, sc, col):
    for i, ch in enumerate(s):
        gl = F[ch]
        ox = x + i * 6 * sc
        for c in range(5):
            for r in range(7):
                if gl[c] >> r & 1:
                    for dy in range(sc):
                        base = ((y + r * sc + dy) * W + ox + c * sc) * 3
                        for dx in range(sc):
                            px[base + dx * 3:base + dx * 3 + 3] = bytes(col)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "splash_640x480.png")
    px = bytearray(W * H * 3)
    for y in range(H):
        t = y / (H - 1)
        c = tuple(int(TOP[k] + (BOT[k] - TOP[k]) * t) for k in range(3))
        row = bytes(c) * W
        px[y * W * 3:(y + 1) * W * 3] = row

    def rect(x, y, w, h, col):
        for yy in range(y, y + h):
            b = (yy * W + x) * 3
            px[b:b + w * 3] = bytes(col) * w

    head, hsc = "SQUEEZEBOX", 8
    hw = text_w(head, hsc)
    hx, hy = (W - hw) // 2, 190
    draw_text(px, head, hx, hy, hsc, WHITE)
    rect(hx, hy + 7 * hsc + 12, hw, 4, TEAL)          # rule under headline
    sub, ssc = "RG35XX H", 4
    sw = text_w(sub, ssc)
    draw_text(px, sub, (W - sw) // 2, hy + 7 * hsc + 28, ssc, AMBER)
    ver, vsc = "SQUEEZEPLAY 8.0", 2
    vw = text_w(ver, vsc)
    draw_text(px, ver, (W - vw) // 2, 420, vsc, GRAY)

    raw = bytearray()
    for y in range(H):
        raw.append(0)
        raw += px[y * W * 3:(y + 1) * W * 3]
    png = bytearray(struct.pack("8B", 137, 80, 78, 71, 13, 10, 26, 10))

    def chunk(typ, body):
        png.extend(struct.pack(">I", len(body)) + typ + body)
        png.extend(struct.pack(">I", zlib.crc32(typ + body) & 0xFFFFFFFF))

    chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    chunk(b"IEND", b"")
    with open(out, "wb") as fh:
        fh.write(png)
    print("wrote %s (%d bytes)" % (out, len(png)))


if __name__ == "__main__":
    main()
