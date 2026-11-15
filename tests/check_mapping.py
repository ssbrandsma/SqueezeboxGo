#!/usr/bin/env python3
"""Input-mapping validator (Agent 4 contract, v1 schema).

Target files: ui/input/*.json (primary), ui/input/*.conf (KEY=Action),
and ui/input/*.map (evdev2jive grammar, see ui/input/README.md).

JSON schema (v1, physical button -> canonical Jive action):
  {"device": "rg35xx-h", "bindings": {"ButtonA": "Select", ...}}

Rules (errors -> FAIL):
  * file must parse; "bindings" must be a non-empty object (JSON)
  * every required canonical action (interface-contracts.md) bound >= 1
  * every bound action must be canonical or optional (no invented actions)
  * .conf: no duplicate physical keys, no blank sides
  * .map (evdev2jive): grammar valid; no duplicate inputs; all 13
    contract physical inputs bound; all reviewed contract output keys
    present (arrows/enter/end + Jive char-path keys, see ui/input/*.map
    header comments for the OUT->action rationale)
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

# evdev2jive .map grammar (ui/input/rg35xxh.map is the reference).
MAP_DIRECTIVES = {"device": 1, "grab": 1, "tap_ms": 1, "debounce_ms": 1,
                  "rep_delay_ms": 1, "rep_period_ms": 1}
MAP_REQUIRED_INPUTS = ["BTN_DPAD_UP", "BTN_DPAD_DOWN", "BTN_DPAD_LEFT",
                       "BTN_DPAD_RIGHT", "BTN_EAST", "BTN_SOUTH", "BTN_NORTH",
                       "BTN_WEST", "BTN_START", "BTN_SELECT", "BTN_TL",
                       "BTN_TR", "BTN_TL2", "BTN_TR2"]
# Reviewed contract outputs: arrows/enter/end + Jive char-path keys
# ('['->now playing, f->favorites, space->pause, z/b->prev/next, -->vol).
MAP_REQUIRED_OUTPUTS = ["KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT",
                        "KEY_ENTER", "KEY_END", "KEY_LEFTBRACE", "KEY_F",
                        "KEY_SPACE", "KEY_Z", "KEY_B", "KEY_MINUS", "KEY_EQUAL"]

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


def _is_code(tok, prefixes=("KEY_", "BTN_")):
    return (tok.startswith(prefixes) and len(tok) > 4
            and all(c.isalnum() or c == "_" for c in tok))


def check_evdev2jive(text):
    errors, warnings = [], []
    seen_inputs, outputs = {}, []
    n_key = 0
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        head = parts[0]
        if head in MAP_DIRECTIVES:
            if len(parts) != 1 + MAP_DIRECTIVES[head]:
                errors.append(f"line {n}: directive '{head}' takes "
                              f"{MAP_DIRECTIVES[head]} arg(s)")
            elif head != "device":
                try:
                    if int(parts[1]) < 0:
                        raise ValueError
                except ValueError:
                    errors.append(f"line {n}: directive '{head}' needs a "
                                  "non-negative integer")
            continue
        if head == "key":
            # key IN OUT tap|hold [long MS LONGKEY]
            n_key += 1
            if len(parts) not in (4, 7):
                errors.append(f"line {n}: want 'key IN OUT tap|hold "
                              "[long MS LONGKEY]'")
                continue
            _, inc, outc, mode = parts[:4]
            if not _is_code(inc):
                errors.append(f"line {n}: bad input code '{inc}'")
            if not _is_code(outc, ("KEY_",)):
                errors.append(f"line {n}: bad output code '{outc}'")
            if mode not in ("tap", "hold"):
                errors.append(f"line {n}: mode must be tap|hold, "
                              f"got '{mode}'")
            if inc in seen_inputs:
                errors.append(f"line {n}: duplicate input '{inc}' (first on "
                              f"line {seen_inputs[inc]})")
            else:
                seen_inputs[inc] = n
            outputs.append(outc)
            if len(parts) == 7:
                if parts[4] != "long":
                    errors.append(f"line {n}: 5th field must be 'long'")
                try:
                    if int(parts[5]) <= 0:
                        raise ValueError
                except ValueError:
                    errors.append(f"line {n}: long timeout must be a "
                                  "positive integer")
                if not _is_code(parts[6], ("KEY_",)):
                    errors.append(f"line {n}: bad long key '{parts[6]}'")
                else:
                    outputs.append(parts[6])
            continue
        if head == "axis":
            # axis ABS center C press P release R neg KEY pos KEY [flip]
            n_parts = len(parts)
            ok = (n_parts in (12, 13) and parts[2] == "center"
                  and parts[4] == "press" and parts[6] == "release"
                  and parts[8] == "neg" and parts[10] == "pos")
            if not ok or (n_parts == 13 and parts[12] != "flip"):
                errors.append(f"line {n}: want 'axis ABS center C press P "
                              "release R neg KEY pos KEY [flip]'")
                continue
            if not parts[1].startswith("ABS_"):
                errors.append(f"line {n}: bad axis '{parts[1]}'")
            if parts[1] in seen_inputs:
                errors.append(f"line {n}: duplicate axis '{parts[1]}'")
            else:
                seen_inputs[parts[1]] = n
            try:
                c, p, r = int(parts[3]), int(parts[5]), int(parts[7])
                if not (c > p > r >= 0):
                    errors.append(f"line {n}: want center > press > "
                                  "release >= 0")
            except ValueError:
                errors.append(f"line {n}: center/press/release must be ints")
            for kc in (parts[9], parts[11]):
                if not _is_code(kc, ("KEY_",)):
                    errors.append(f"line {n}: bad axis key '{kc}'")
                else:
                    outputs.append(kc)
            continue
        errors.append(f"line {n}: unknown statement '{head}' "
                      "(want key|axis|device|grab|tap_ms|debounce_ms|"
                      "rep_delay_ms|rep_period_ms)")
    if n_key == 0:
        errors.append("no 'key' statements")
    missing_in = [c for c in MAP_REQUIRED_INPUTS if c not in seen_inputs]
    if missing_in:
        errors.append("missing required inputs: " + ", ".join(missing_in))
    missing_out = [c for c in MAP_REQUIRED_OUTPUTS if c not in outputs]
    if missing_out:
        errors.append("missing required outputs: " + ", ".join(missing_out))
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
        if t.endswith(".json"):
            checker = check_json
        elif t.endswith(".map"):
            checker = check_evdev2jive
        else:
            checker = check_conf
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
