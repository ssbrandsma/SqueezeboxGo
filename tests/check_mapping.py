#!/usr/bin/env python3
"""Input-mapping validator (Agent 4 contract, v1 schema).

Target files: ui/input/*.json (primary) and ui/input/*.conf (KEY=Action).

JSON schema (v1, physical button -> canonical Jive action):
  {"device": "rg35xx-h", "bindings": {"ButtonA": "Select", ...}}

Rules (errors -> FAIL):
  * file must parse; "bindings" must be a non-empty object (JSON)
  * every required canonical action (interface-contracts.md) bound >= 1
  * every bound action must be canonical or optional (no invented actions)
  * .conf: no duplicate physical keys, no blank sides
Warnings: optional stick-scroll actions unbound; unknown sections.

Exit codes: 0 PASS, 1 FAIL, 3 NOT RUN (no mapping files yet).
"""

import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qa_lib import repo_root, emit, PASS, FAIL, NOTRUN

REQUIRED_ACTIONS = ["Up", "Down", "Left", "Right", "Select", "Back",
                    "NowPlaying", "Favorites", "PlayPause", "Home",
                    "Prev", "Next", "VolDown", "VolUp"]
OPTIONAL_ACTIONS = ["ScrollUp", "ScrollDown", "ScrollLeft", "ScrollRight",
                    "VolMute", "BrightnessUp", "BrightnessDown", "Power"]
KNOWN_ACTIONS = set(REQUIRED_ACTIONS + OPTIONAL_ACTIONS)

PATTERNS = ["ui/input/*.json", "ui/input/*.conf", "ui/input/*.map"]


def find_targets(root):
    out = []
    for pat in PATTERNS:
        out.extend(glob.glob(os.path.join(root, pat)))
    return sorted(p for p in out if os.path.isfile(p))


def check_json(text):
    errors, warnings = [], []
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"], []
    if not isinstance(data, dict):
        return ["top level must be an object"], []
    bindings = data.get("bindings")
    if not isinstance(bindings, dict) or not bindings:
        return ['missing/empty "bindings" object'], []
    actions = list(bindings.values())
    for phys, act in bindings.items():
        if not isinstance(phys, str) or not phys.strip():
            errors.append("empty physical key name")
        if act not in KNOWN_ACTIONS:
            errors.append(f"unknown action '{act}' on '{phys}' "
                          f"(canonical: {', '.join(REQUIRED_ACTIONS)})")
    missing = [a for a in REQUIRED_ACTIONS if a not in actions]
    if missing:
        errors.append("unbound required actions: " + ", ".join(missing))
    opt_missing = [a for a in OPTIONAL_ACTIONS[:4] if a not in actions]
    if opt_missing:
        warnings.append("optional stick-scroll unbound: " +
                        ", ".join(opt_missing))
    return errors, warnings


def check_conf(text):
    errors, warnings = [], []
    seen, actions = {}, []
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            errors.append(f"line {n}: expected KEY=Action")
            continue
        key, act = (s.strip() for s in line.split("=", 1))
        if not key or not act:
            errors.append(f"line {n}: blank key or action")
            continue
        if key in seen:
            errors.append(f"line {n}: duplicate key '{key}' "
                          f"(first on line {seen[key]})")
        seen[key] = n
        actions.append(act)
        if act not in KNOWN_ACTIONS:
            errors.append(f"line {n}: unknown action '{act}'")
    missing = [a for a in REQUIRED_ACTIONS if a not in actions]
    if missing:
        errors.append("unbound required actions: " + ", ".join(missing))
    return errors, warnings


def main(argv=None):
    ap = argparse.ArgumentParser(description="Validate input mapping files.")
    ap.add_argument("files", nargs="*", default=None)
    ap.add_argument("--root", default=None)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    root = repo_root(args.root)
    targets = ([os.path.join(root, f) if not os.path.isabs(f) else f
                for f in args.files] if args.files else find_targets(root))
    targets = [t for t in targets if os.path.isfile(t)]
    if not targets:
        return emit("mapping", NOTRUN,
                    ["no mapping files under ui/input/ yet"],
                    json_mode=args.json)
    details, failed = [], []
    for t in targets:
        rel = os.path.relpath(t, root)
        try:
            with open(t, "r", encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError) as e:
            failed.append(rel)
            details.append(f"{rel}: ERROR: cannot read: {e}")
            continue
        checker = check_json if t.endswith(".json") else check_conf
        errors, warnings = checker(text)
        if errors:
            failed.append(rel)
            for e in errors:
                details.append(f"{rel}: ERROR: {e}")
        else:
            details.append(f"{rel}: mapping ok")
        for w in warnings:
            details.append(f"{rel}: warn: {w}")
    details.append(f"checked {len(targets)} file(s), {len(failed)} failed")
    return emit("mapping", FAIL if failed else PASS, details,
                json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
