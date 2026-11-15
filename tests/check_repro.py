#!/usr/bin/env python3
"""Reproducibility helper: env check + sha256 manifests + rebuild compare.

Subcommands:
  env                  verify SOURCE_DATE_EPOCH is set to an integer
  manifest DIR -o OUT  write sorted "sha256  relpath" manifest of DIR
                       (skips .git/; --exclude GLOB repeatable)
  compare A B          diff two manifests (rebuild-twice check)

Exit codes: 0 PASS, 1 FAIL, 4 BLOCKED (missing dir/tool).
With --json, prints a single {"check": "repro:<sub>", ...} object.
"""

import argparse
import fnmatch
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import repo_root, emit, PASS, FAIL, BLOCKED


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def iter_files(top, excludes):
    out = []
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = [d for d in dirnames if d != ".git"]
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, top)
            if any(fnmatch.fnmatch(rel, pat) for pat in excludes):
                continue
            out.append((rel, full))
    return sorted(out)


def cmd_env(args):
    val = os.environ.get("SOURCE_DATE_EPOCH", "")
    if not val:
        return emit("repro:env", FAIL,
                    ["SOURCE_DATE_EPOCH is not set "
                     "(build contract requires it; e.g. export "
                     "SOURCE_DATE_EPOCH=$(git log -1 --format=%ct))"],
                    json_mode=args.json)
    try:
        iv = int(val)
        if iv < 0:
            raise ValueError
    except ValueError:
        return emit("repro:env", FAIL,
                    [f"SOURCE_DATE_EPOCH={val!r} is not a non-negative int"],
                    json_mode=args.json)
    return emit("repro:env", PASS,
                [f"SOURCE_DATE_EPOCH={val} ok"], json_mode=args.json)


def cmd_manifest(args):
    top = os.path.abspath(args.dir)
    if not os.path.isdir(top):
        return emit("repro:manifest", BLOCKED,
                    [f"not a directory: {args.dir}"], json_mode=args.json)
    entries = iter_files(top, args.exclude or [])
    try:
        with open(args.output, "w", encoding="utf-8") as f:
            for rel, full in entries:
                f.write(f"{sha256_of(full)}  {rel}\n")
    except OSError as e:
        return emit("repro:manifest", BLOCKED,
                    [f"cannot write {args.output}: {e}"], json_mode=args.json)
    return emit("repro:manifest", PASS,
                [f"wrote {len(entries)} entries -> {args.output}"],
                json_mode=args.json)


def load_manifest(path):
    d = {}
    with open(path, "r", encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n")
            if not line.strip():
                continue
            parts = line.split(None, 1)
            if len(parts) != 2 or len(parts[0]) != 64:
                raise ValueError(f"{path}:{n}: malformed manifest line")
            d[parts[1].strip()] = parts[0]
    return d


def cmd_compare(args):
    try:
        a = load_manifest(args.a)
        b = load_manifest(args.b)
    except (OSError, ValueError) as e:
        return emit("repro:compare", BLOCKED, [str(e)], json_mode=args.json)
    details = []
    for rel in sorted(set(a) | set(b)):
        if rel not in a:
            details.append(f"added in B: {rel}")
        elif rel not in b:
            details.append(f"missing in B: {rel}")
        elif a[rel] != b[rel]:
            details.append(f"CHANGED: {rel}")
    if details:
        details.append(f"{len(details)} difference(s): rebuild NOT reproducible")
        return emit("repro:compare", FAIL, details, json_mode=args.json)
    return emit("repro:compare", PASS,
                [f"{len(a)} files identical: rebuild reproducible"],
                json_mode=args.json)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Reproducibility helper.")
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    # NB: --json is accepted both before and after the subcommand so the
    # build-and-check runner can append it uniformly.
    e = sub.add_parser("env", help="Check SOURCE_DATE_EPOCH.")
    e.add_argument("--json", action="store_true",
                   default=argparse.SUPPRESS)
    m = sub.add_parser("manifest", help="Write sha256 manifest.")
    m.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    m.add_argument("dir", help="Directory to hash.")
    m.add_argument("-o", "--output", required=True, help="Output manifest.")
    m.add_argument("--exclude", action="append", default=[],
                   help="Exclude glob (repeatable).")
    c = sub.add_parser("compare", help="Compare two manifests.")
    c.add_argument("a")
    c.add_argument("b")
    c.add_argument("--json", action="store_true", default=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    if not hasattr(args, "json"):
        args.json = False
    args.root = repo_root(args.root)
    if args.cmd == "env":
        return cmd_env(args)
    if args.cmd == "manifest":
        return cmd_manifest(args)
    return cmd_compare(args)


if __name__ == "__main__":
    sys.exit(main())
