#!/usr/bin/env python3
"""LIVE-COLOR-TEST (one-shot, human-watch session).

Fills /dev/fb0 solid red, green, blue with pauses between colors so a
human watcher can confirm whether fb0 reaches the LCD, then restores to
black and restarts the stock frontend. Fully reversible.

Coordinated session procedure (TWO people / shells):
  1. Watcher looks at the device LCD.
  2. Operator stops the frontend first (validated Phase 2 procedure):
         sudo systemctl stop launcher.service
         # poll until empty (up to 60 s):
         while pidof dmenu.bin; do sleep 2; done
  3. Operator runs (AS ROOT — needs fb0 + systemctl):
         sudo python3 color-fill.py [--hold SECONDS]
  4. Watcher reports after EACH color: full-screen color? partial?
     unchanged? Note exact coverage.
  5. Script ends black + frontend restarted by itself. Operator verifies:
         systemctl is-active launcher.service; pidof dmenu.bin

Expected outcomes:
  - Full R/G/B frames in order  => fb0 is (a) visible path; SDL1.2-fbcon
    output reaches the panel (DE routes fb0). PoC video viable as-is.
  - Unchanged / frozen dmenu     => visible layer is disp-direct; PoC needs
    the disp route or layer-attach work. No fbcon video claim allowed.
  - Partial / offset / wrapped   => geometry mismatch (stride/mode); record
    exact appearance for the UI agent.

Geometry: queried live via FBIOGET_VSCREENINFO (never assumed). Pixel
format assumed from bpp (16=>RGB565, 32=>XRGB8888); aborts otherwise.
"""
import fcntl
import mmap
import struct
import subprocess
import sys
import time

FB = "/dev/fb0"
FBIOGET_VSCREENINFO = 0x4600


def get_mode(f):
    v = fcntl.ioctl(f, FBIOGET_VSCREENINFO, b"\x00" * 160)
    g = lambda o: struct.unpack("I", v[o:o + 4])[0]  # noqa: E731
    return {"xres": g(0), "yres": g(4), "bpp": g(24)}


def fill(f, nbytes, pixel: bytes):
    f.seek(0)
    chunk = pixel * (65536 // len(pixel))
    remaining = nbytes
    while remaining > 0:
        piece = chunk[:remaining] if remaining < len(chunk) else chunk
        f.write(piece)
        remaining -= len(piece)
    f.flush()


def main(argv):
    hold = 4.0
    if len(argv) == 3 and argv[1] == "--hold":
        hold = float(argv[2])
    elif len(argv) != 1:
        print("usage: sudo python3 color-fill.py [--hold SECONDS]", file=sys.stderr)
        return 2

    f = open(FB, "r+b")
    mode = get_mode(f)
    xres, yres, bpp = mode["xres"], mode["yres"], mode["bpp"]
    print(f"[color-fill] mode: {xres}x{yres}x{bpp}", flush=True)

    if bpp == 16:
        colors = {"RED": b"\x00\xf8", "GREEN": b"\xe0\x07", "BLUE": b"\x1f\x00"}
        black = b"\x00\x00"
    elif bpp == 32:
        colors = {"RED": b"\x00\x00\xff\x00", "GREEN": b"\x00\xff\x00\x00",
                  "BLUE": b"\xff\x00\x00\x00"}
        black = b"\x00\x00\x00\x00"
    else:
        print(f"[color-fill] REFUSE: unsupported bpp={bpp}", file=sys.stderr)
        return 1

    nbytes = xres * yres * (bpp // 8)
    # Sanity cap: frame must fit the classic 1280x1024x32 maximum (5 MB).
    if nbytes <= 0 or nbytes > 5 * 1024 * 1024:
        print(f"[color-fill] REFUSE: insane frame size {nbytes}", file=sys.stderr)
        return 1

    try:
        for name, px in colors.items():
            print(f"[color-fill] FILL {name} for {hold}s -- WATCHER: report now",
                  flush=True)
            fill(f, nbytes, px)
            time.sleep(hold)
    finally:
        print("[color-fill] restoring BLACK", flush=True)
        try:
            fill(f, nbytes, black)
        finally:
            f.close()
        print("[color-fill] restarting frontend", flush=True)
        r = subprocess.run(["systemctl", "start", "launcher.service"])
        print(f"[color-fill] systemctl start exit={r.returncode}", flush=True)
        time.sleep(6)
        q = subprocess.run(["pidof", "dmenu.bin"], capture_output=True, text=True)
        print(f"[color-fill] dmenu pids: {q.stdout.strip() or '(NONE)'}", flush=True)
    print("[color-fill] DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
