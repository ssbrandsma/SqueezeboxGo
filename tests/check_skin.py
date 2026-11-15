#!/usr/bin/env python3
"""Skin validator: 640x480 = 2x integer scale of the QVGA Radio skin.

Target: ui/skins/*/skin.json manifest (v1):
  {"name": "...", "width": 640, "height": 480,
   "base": {"width": 320, "height": 240},
   "assets": ["bg.png", ...]}   # paths relative to the manifest dir

Rules (errors -> FAIL):
  * manifest parses; width==640, height==480; base==320x240 (scale 2x)
  * every listed asset exists, is a valid PNG (signature + IHDR via
    stdlib struct, no PIL needed), has even width/height (2x-scaleable)
    and fits inside the 640x480 canvas
Warnings: assets dir contains PNGs not listed in the manifest.

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no skin manifests yet).
"""

import argparse
import glob
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import repo_root, emit, PASS, FAIL, NOTRUN

WANT_W, WANT_H = 640, 480
BASE_W, BASE_H = 320, 240
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def png_size(path):
    """Return (w, h) from IHDR or raise ValueError."""
    with open(path, "rb") as f:
        head = f.read(33)
    if len(head) < 33 or head[:8] != PNG_SIG:
        raise ValueError("not a PNG (bad signature)")
    length, ctype = struct.unpack(">I4s", head[8:16])
    if ctype != b"IHDR" or length != 13:
        raise ValueError("first chunk is not IHDR")
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def check_manifest(mpath):
    errors, warnings, notes = [], [], []
    d = os.path.dirname(mpath)
    try:
        with open(mpath, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e:
        return [f"manifest unreadable: {e}"], [], []
    if not isinstance(data, dict):
        return ["top level must be an object"], [], []
    w, h = data.get("width"), data.get("height")
    if (w, h) != (WANT_W, WANT_H):
        errors.append(f"canvas must be {WANT_W}x{WANT_H}, got {w}x{h}")
    base = data.get("base", {})
    if (base.get("width"), base.get("height")) != (BASE_W, BASE_H):
        errors.append(f"base must be QVGA {BASE_W}x{BASE_H} (2x integer "
                      f"scale), got {base.get('width')}x{base.get('height')}")
    assets = data.get("assets")
    if not isinstance(assets, list) or not assets:
        errors.append('"assets" must be a non-empty list')
        return errors, warnings, notes
    for a in assets:
        ap = os.path.normpath(os.path.join(d, a))
        if not ap.startswith(os.path.abspath(d) + os.sep):
            errors.append(f"asset escapes skin dir: {a}")
            continue
        if not os.path.isfile(ap):
            errors.append(f"missing asset: {a}")
            continue
        try:
            aw, ah = png_size(ap)
        except (OSError, ValueError) as e:
            errors.append(f"asset {a}: {e}")
            continue
        if aw % 2 or ah % 2:
            errors.append(f"asset {a}: {aw}x{ah} not even "
                          "(breaks 2x integer scale)")
        elif aw > WANT_W or ah > WANT_H:
            errors.append(f"asset {a}: {aw}x{ah} exceeds canvas")
        else:
            notes.append(f"asset {a}: {aw}x{ah} ok")
    on_disk = {f for f in os.listdir(d) if f.lower().endswith(".png")}
    unlisted = sorted(on_disk - {os.path.basename(a) for a in assets
                                 if "/" not in a})
    if unlisted:
        warnings.append("unlisted PNGs in skin dir: " + ", ".join(unlisted))
    return errors, warnings, notes


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate 640x480 skins.")
    ap.add_argument("files", nargs="*", default=None,
                    help="Manifests (default: ui/skins/*/skin.json).")
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    root = repo_root(args.root)
    targets = ([os.path.join(root, f) if not os.path.isabs(f) else f
                for f in args.files] if args.files
               else sorted(glob.glob(os.path.join(root, "ui", "skins", "*",
                                                  "skin.json"))))
    targets = [t for t in targets if os.path.isfile(t)]
    if not targets:
        return emit("skin", NOTRUN,
                    ["no skin manifests under ui/skins/ yet"],
                    json_mode=args.json)
    details, failed = [], []
    for t in targets:
        rel = os.path.relpath(t, root)
        errors, warnings, notes = check_manifest(t)
        if errors:
            failed.append(rel)
            for e in errors:
                details.append(f"{rel}: ERROR: {e}")
        else:
            details.append(f"{rel}: skin ok "
                           f"({WANT_W}x{WANT_H}, 2x of "
                           f"{BASE_W}x{BASE_H})")
        for x in notes:
            details.append(f"{rel}: {x}")
        for x in warnings:
            details.append(f"{rel}: warn: {x}")
    details.append(f"checked {len(targets)} skin(s), {len(failed)} failed")
    return emit("skin", FAIL if failed else PASS, details,
                json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
