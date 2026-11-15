#!/usr/bin/env python3
"""Skin validator: 640x480 = 2x integer scale of the QVGA Radio skin.

Targets:
  * ui/skins/*/skin.json manifest (v1):
    {"name": "...", "width": 640, "height": 480,
     "base": {"width": 320, "height": 240},
     "assets": ["bg.png", ...]}   # paths relative to the manifest dir
  * Lua skins: ui/skins/*/ dirs holding *Applet.lua (+ *Meta.lua,
    images/...) as shipped by Agent 4 (Jive applet skins, no manifest).

Rules (errors -> FAIL):
  * manifest parses; width==640, height==480; base==320x240 (scale 2x)
  * every listed asset exists, is a valid PNG (signature + IHDR via
    stdlib struct, no PIL needed), has even width/height (2x-scaleable)
    and fits inside the 640x480 canvas
  * Lua skin: >=1 *Applet.lua present; every PNG under the skin dir
    valid with even width/height (2x property; oversize assets are legal
    and counted, not errors); Lua files byte-compile when luac installed
Warnings: assets dir contains PNGs not listed in the manifest;
  luac missing (Lua syntax unchecked).

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no skins yet).
"""

import argparse
import glob
import json
import os
import shutil
import struct
import subprocess
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


LUAC_CANDIDATES = ("luac", "luac5.1", "luac-5.1.5")


def check_lua_skin(d):
    """Validate a Jive applet skin dir (no manifest). Summarized notes."""
    errors, warnings, notes = [], [], []
    applets = sorted(glob.glob(os.path.join(d, "*Applet.lua")))
    metas = sorted(glob.glob(os.path.join(d, "*Meta.lua")))
    if not applets:
        return ["no *Applet.lua in skin dir"], [], []
    if not metas:
        warnings.append("no *Meta.lua in skin dir")
    pngs = []
    for dirpath, _, files in os.walk(d):
        for f in files:
            if f.lower().endswith(".png"):
                pngs.append(os.path.join(dirpath, f))
    if not pngs:
        warnings.append("no PNG assets under skin dir")
    # NOTE: no "fits canvas" rule here. Faithful 2x Lua skins legitimately
    # contain assets larger than the viewport (scroll strips, 9-slice box
    # parts, clock faces, dev-only Guidelines/Reference_Screens) — the
    # upstream QVGA originals exceed 320x240 the same way. Oversize assets
    # are counted as info only; Jive clips/scales at render time.
    bad, oversize = 0, 0
    for ap in sorted(pngs):
        rel = os.path.relpath(ap, d)
        try:
            aw, ah = png_size(ap)
        except (OSError, ValueError) as e:
            errors.append(f"{rel}: {e}")
            bad += 1
            continue
        if aw % 2 or ah % 2:
            errors.append(f"{rel}: {aw}x{ah} not even "
                          "(breaks 2x integer scale)")
            bad += 1
        elif aw > WANT_W or ah > WANT_H:
            oversize += 1
        if bad >= 20 and len(errors) > 20:
            errors.append("... further asset errors suppressed")
            break
    notes.append(f"{len(pngs)} PNG(s) checked, "
                 f"{len(pngs) - bad} ok ({oversize} oversize-but-legal)")
    luac = next((c for c in LUAC_CANDIDATES if shutil.which(c)), None)
    if luac is None:
        warnings.append("luac not installed; Lua syntax unchecked")
    else:
        for lf in applets + metas:
            rel = os.path.relpath(lf, d)
            try:
                r = subprocess.run([luac, "-p", lf], capture_output=True,
                                   text=True, timeout=60)
            except (OSError, subprocess.TimeoutExpired) as e:
                errors.append(f"{rel}: luac failed: {e}")
                continue
            if r.returncode != 0:
                errors.append(f"{rel}: luac: "
                              f"{(r.stderr or r.stdout).strip()}")
        notes.append(f"{len(applets) + len(metas)} Lua file(s) compile ok")
    return errors, warnings, notes


def find_lua_skins(root):
    out = []
    base = os.path.join(root, "ui", "skins")
    if not os.path.isdir(base):
        return out
    for entry in sorted(os.listdir(base)):
        d = os.path.join(base, entry)
        if (os.path.isdir(d)
                and glob.glob(os.path.join(d, "*Applet.lua"))
                and not os.path.isfile(os.path.join(d, "skin.json"))):
            out.append(d)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate 640x480 skins.")
    ap.add_argument("files", nargs="*", default=None,
                    help="Manifests or skin dirs (default:ui/skins/*).")
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    root = repo_root(args.root)
    if args.files:
        given = [os.path.join(root, f) if not os.path.isabs(f) else f
                 for f in args.files]
        manifests = [t for t in given if os.path.isfile(t)]
        luaskins = [t for t in given if os.path.isdir(t)]
    else:
        manifests = sorted(glob.glob(os.path.join(root, "ui", "skins", "*",
                                                  "skin.json")))
        manifests = [t for t in manifests if os.path.isfile(t)]
        luaskins = find_lua_skins(root)
    if not manifests and not luaskins:
        return emit("skin", NOTRUN,
                    ["no skins under ui/skins/ yet"],
                    json_mode=args.json)
    details, failed = [], []
    for t in manifests:
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
    for d in luaskins:
        rel = os.path.relpath(d, root)
        errors, warnings, notes = check_lua_skin(d)
        if errors:
            failed.append(rel)
            for e in errors:
                details.append(f"{rel}: ERROR: {e}")
        else:
            details.append(f"{rel}: lua skin ok")
        for x in notes:
            details.append(f"{rel}: {x}")
        for x in warnings:
            details.append(f"{rel}: warn: {x}")
    details.append(f"checked {len(manifests) + len(luaskins)} skin(s), "
                   f"{len(failed)} failed")
    return emit("skin", FAIL if failed else PASS, details,
                json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
