#!/usr/bin/env python3
"""test-display-trial.py — host-side tests for stock/bundle/display-trial.py.

No framebuffer needed: exercises --save-png rendering + CLI contract.
TAP-ish output (ok/not ok), exit 1 on any failure.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
TRIAL = os.path.join(HERE, "..", "bundle", "display-trial.py")

passed, failed, n = 0, 0, 0


def check(name, cond, detail=""):
    global passed, failed, n
    n += 1
    if cond:
        passed += 1
        print("ok %d - %s" % (n, name))
    else:
        failed += 1
        print("not ok %d - %s %s" % (n, name, detail))


def read_png(path):
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "bad signature"
    w, h = struct.unpack(">II", d[16:24])
    i = d.find(b"IDAT")
    ln = struct.unpack(">I", d[i - 4:i])[0]
    raw = zlib.decompress(d[i + 4:i + 4 + ln])
    stride = w * 4 + 1

    def get(x, y):
        o = y * stride + 1 + x * 4
        return tuple(raw[o:o + 4])

    return w, h, get


tmp = tempfile.mkdtemp(prefix="trial-test-")
r1 = subprocess.run([sys.executable, TRIAL, "--save-png", tmp + "/a"],
                    capture_output=True, text=True)
check("save-png exits 0", r1.returncode == 0, r1.stderr[-200:])
r2 = subprocess.run([sys.executable, TRIAL, "--save-png", tmp + "/b"],
                    capture_output=True, text=True)
check("second run exits 0", r2.returncode == 0)

import filecmp
same = all(
    filecmp.cmp("%s/a/attempt-%d.png" % (tmp, i),
                "%s/b/attempt-%d.png" % (tmp, i), shallow=False)
    for i in range(1, 7))
check("rebuild-twice byte-identical (6/6)", same)

expect = {1: (1280, 1024), 2: (640, 480), 3: (1280, 1024),
          4: (640, 480), 5: (640, 480), 6: (512, 384)}
dims_ok = True
for i, (ew, eh) in expect.items():
    w, h, _ = read_png("%s/a/attempt-%d.png" % (tmp, i))
    dims_ok = dims_ok and (w, h) == (ew, eh)
check("all 6 geometries as specified", dims_ok)

# attempt 2 (640x480x16): white border, non-bg digit, quantized navy bg
_, _, g2 = read_png("%s/a/attempt-2.png" % tmp)
check("attempt-2 border white", g2(320, 1)[:3] == (255, 255, 255))
check("attempt-2 digit drawn", g2(320, 230) == (255, 255, 255, 255))
check("attempt-2 bg quantized navy", g2(100, 400) == (8, 12, 24, 255))

# attempt 3: picture confined to top-left 640x480 of 1280x1024
_, _, g3 = read_png("%s/a/attempt-3.png" % tmp)
outside = all(g3(x, y) == (8, 12, 24, 255)
              for x, y in ((700, 100), (1200, 500), (700, 900), (100, 900)))
check("attempt-3 region confined", outside)
check("attempt-3 region border", g3(320, 1)[:3] == (255, 255, 255))

# attempt 4 is 32-bit: pure red bar must be exact (no quantization)
_, _, g4 = read_png("%s/a/attempt-4.png" % tmp)
check("attempt-4 32-bit red exact", g4(50, 450) == (255, 0, 0, 255))

# CLI contract
r = subprocess.run([sys.executable, TRIAL, "--help"], capture_output=True)
check("--help exits 0", r.returncode == 0)

print("---\npass=%d fail=%d total=%d" % (passed, failed, n))
sys.exit(1 if failed else 0)
