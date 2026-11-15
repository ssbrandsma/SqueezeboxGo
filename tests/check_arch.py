#!/usr/bin/env python3
"""Architecture + shared-library dependency validator (build gate).

For every ELF binary found under the given search paths:
  * `file` must report the expected machine (default: ARM aarch64, the
    WP1 target; use --expect x86-64 to validate host tools instead).
  * `readelf -d` NEEDED entries must all match the allowlist
    (tests/data/needed-allowlist.txt, fnmatch per line).
  * The PT_INTERP program interpreter must match --interp when the
    binary has one.

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no ELF files found),
4 BLOCKED (file/readelf missing). See tests/qa_lib.py.
"""

import argparse
import fnmatch
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import (repo_root, emit, which, run, PASS, FAIL, NOTRUN, BLOCKED)

ELF_MAGIC = b"\x7fELF"

EXPECT_TAG = {
    "aarch64": "ARM aarch64",
    "x86-64": "x86-64",
    "arm": "ARM,",
}

DEFAULT_PATHS = ["build", "platform", "squeezeplay", "standalone", "ui", "audio"]


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == ELF_MAGIC
    except OSError:
        return False


def find_elves(root, subpaths):
    found = []
    for sub in subpaths:
        base = os.path.join(root, sub)
        if os.path.isfile(base):
            if is_elf(base):
                found.append(base)
            continue
        if not os.path.isdir(base):
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d != ".git"]
            for name in filenames:
                p = os.path.join(dirpath, name)
                if is_elf(p):
                    found.append(p)
    return sorted(found)


def load_allowlist(path):
    pats = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                pats.append(line)
    return pats


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate ELF arch + NEEDED deps.")
    ap.add_argument("paths", nargs="*", default=DEFAULT_PATHS,
                    help="Files or dirs to scan (default: artifact dirs).")
    ap.add_argument("--root", default=None, help="Repo root (autodetected).")
    ap.add_argument("--expect", default="aarch64",
                    choices=sorted(EXPECT_TAG),
                    help="Expected machine (default: aarch64).")
    ap.add_argument("--allowlist", default=None,
                    help="NEEDED allowlist file.")
    ap.add_argument("--interp", default="/lib/ld-linux-aarch64.so.1",
                    help="Expected PT_INTERP ('' to skip).")
    ap.add_argument("--json", action="store_true", help="JSON output.")
    args = ap.parse_args(argv)

    root = repo_root(args.root)
    allow_path = args.allowlist or os.path.join(
        root, "tests", "data", "needed-allowlist.txt")
    details = []
    problems = []

    if which("file") is None:
        return emit("arch", BLOCKED, ["required tool 'file' not found on PATH"],
                    json_mode=args.json)
    if which("readelf") is None:
        return emit("arch", BLOCKED, ["required tool 'readelf' not found on PATH"],
                    json_mode=args.json)
    if not os.path.isfile(allow_path):
        return emit("arch", BLOCKED, [f"allowlist not found: {allow_path}"],
                    json_mode=args.json)
    allow = load_allowlist(allow_path)

    elves = find_elves(root, args.paths)
    if not elves:
        return emit("arch", NOTRUN,
                    [f"no ELF binaries under {', '.join(args.paths)} "
                     "(nothing built yet)"],
                    json_mode=args.json)

    tag = EXPECT_TAG[args.expect]
    for elf in elves:
        rel = os.path.relpath(elf, root)
        file_out = run(["file", "-b", elf]).stdout.strip()
        if tag not in file_out:
            problems.append(f"{rel}: arch mismatch (want {args.expect}): {file_out}")
            details.append(f"{rel}: ARCH MISMATCH: {file_out}")
        else:
            details.append(f"{rel}: arch ok ({file_out.split(',')[0].strip()})")
        rd = run(["readelf", "-d", elf])
        if rd.returncode != 0:
            problems.append(f"{rel}: readelf failed: {rd.stderr.strip()}")
            continue
        for line in rd.stdout.splitlines():
            if "(NEEDED)" in line:
                lib = line.split("[", 1)[1].rstrip("]").strip()
                if any(fnmatch.fnmatch(lib, p) for p in allow):
                    details.append(f"{rel}: NEEDED ok: {lib}")
                else:
                    problems.append(f"{rel}: NEEDED not allowlisted: {lib}")
                    details.append(f"{rel}: NEEDED DENIED: {lib}")
            elif "(INTERPRETER)" in line and args.interp:
                interp = line.split("[", 1)[1].rstrip("]").strip()
                if interp != args.interp:
                    problems.append(f"{rel}: interpreter {interp} "
                                     f"!= {args.interp}")
                    details.append(f"{rel}: INTERP MISMATCH: {interp}")
                else:
                    details.append(f"{rel}: interp ok: {interp}")

    details.append(f"scanned {len(elves)} ELF file(s), "
                   f"{len(problems)} problem(s)")
    if problems:
        return emit("arch", FAIL, details, json_mode=args.json)
    return emit("arch", PASS, details, json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
