#!/usr/bin/env python3
"""ALSA configuration validator.

Targets (default): audio/alsa/**/*.conf, asound.conf*, .asoundrc*.
Checks (errors -> FAIL):
  * balanced { } and ( ); unterminated /* */ comment or " string
  * NUL bytes / non-UTF8 content
Checks (warnings only, listed in output):
  * tab indentation (ALSA accepts it; style prefers spaces)
  * no pcm.!default / defaults.pcm.card definition (node may live in an
    included file, so this cannot be an error at single-file scope)

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no asound files yet).
"""

import argparse
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import repo_root, emit, PASS, FAIL, NOTRUN

PATTERNS = ["audio/alsa/**/*.conf", "audio/alsa/**/asound.conf*",
            "audio/alsa/**/.asoundrc*"]


def find_targets(root):
    out = []
    for pat in PATTERNS:
        out.extend(glob.glob(os.path.join(root, pat), recursive=True))
    return sorted(p for p in out if os.path.isfile(p))


def check_file(path):
    """Return (errors, warnings) string lists for one file."""
    errors, warnings = [], []
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except OSError as e:
        return [f"cannot read: {e}"], []
    if b"\x00" in raw:
        return ["NUL byte present (not a text config)"], []
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        return [f"not valid UTF-8: {e}"], []

    # Strip comments/strings while tracking brace balance.
    i, n = 0, len(text)
    line = 1
    stack = []  # (char, line)
    in_str = False
    in_block = False
    has_default_pcm = ("pcm.!default" in text or "pcm. !default" in text
                       or "defaults.pcm.card" in text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "\n":
            line += 1
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 1
        else:
            if c == '"':
                in_str = True
            elif c == "/" and nxt == "*":
                in_block = True
                i += 1
            elif c == "#":
                while i < n and text[i] != "\n":
                    i += 1
                line += 0  # newline handled next iteration
                continue
            elif c in "{(":
                stack.append((c, line))
            elif c in "})":
                want = "{" if c == "}" else "("
                if not stack or stack[-1][0] != want:
                    errors.append(f"line {line}: unmatched '{c}'")
                else:
                    stack.pop()
        i += 1
    if in_str:
        errors.append("unterminated string literal")
    if in_block:
        errors.append("unterminated /* comment */")
    for ch, ln in reversed(stack):
        errors.append(f"line {ln}: unclosed '{ch}'")
    for n2, l2 in enumerate(text.splitlines(), 1):
        if "\t" in l2:
            warnings.append(f"line {n2}: tab indentation (prefer spaces)")
            break
    if not has_default_pcm:
        warnings.append("no pcm.!default / defaults.pcm.card in this file "
                        "(ok if provided by an include)")
    return errors, warnings


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate ALSA config files.")
    ap.add_argument("files", nargs="*", default=None,
                    help="Files to check (default: audio/alsa/**).")
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    root = repo_root(args.root)
    targets = ([os.path.join(root, f) if not os.path.isabs(f) else f
                for f in args.files] if args.files else find_targets(root))
    targets = [t for t in targets if os.path.isfile(t)]
    if not targets:
        return emit("asound", NOTRUN,
                    ["no ALSA configs under audio/alsa/ yet"],
                    json_mode=args.json)
    details, failed = [], []
    for t in targets:
        rel = os.path.relpath(t, root)
        errors, warnings = check_file(t)
        if errors:
            failed.append(rel)
            for e in errors:
                details.append(f"{rel}: ERROR: {e}")
        else:
            details.append(f"{rel}: syntax ok")
        for w in warnings:
            details.append(f"{rel}: warn: {w}")
    details.append(f"checked {len(targets)} file(s), {len(failed)} failed")
    return emit("asound", FAIL if failed else PASS, details,
                json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
