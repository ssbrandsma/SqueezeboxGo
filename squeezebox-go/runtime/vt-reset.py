#!/usr/bin/env python3
"""vt-reset.py — normalize VT/console state before SDL fbcon starts.

Background: an SDL1.2-fbcon app killed without SDL_Quit cleanup
(SIGTERM/SIGKILL, including our own timeout kills) leaves the console
in KD_GRAPHICS with VT_LOCKSWITCH held. The NEXT SDL app then wedges
forever in VT_WAITACTIVE inside SDL_SetVideoMode (proven by kernel
stack: __vt_event_wait <- vt_waitactive <- vt_ioctl).

This replays exactly what SDL_Quit's FB_LeaveGraphicsMode would have
done: KDSETMODE KD_TEXT + VT_UNLOCKSWITCH. It never switches VTs
(chvt-style switches wedge on this kernel) and never fails the boot:
all errors are reported, exit code reflects success.

Usage: vt-reset.py [--tty PATH] [--dry-run]
"""
import argparse
import fcntl
import sys

KDSETMODE = 0x4B3A
KD_TEXT = 0x00
VT_UNLOCKSWITCH = 0x5602


def reset(tty="/dev/tty0", dry_run=False):
    """Return list of (action, ok, detail). Never raises."""
    actions = [("KDSETMODE KD_TEXT", KDSETMODE, KD_TEXT),
               ("VT_UNLOCKSWITCH", VT_UNLOCKSWITCH, 1)]
    out = []
    if dry_run:
        return [(name, True, "dry-run") for name, _, _ in actions]
    try:
        fd = open(tty, "w")
    except OSError as e:
        return [("open " + tty, False, repr(e))]
    try:
        for name, req, arg in actions:
            try:
                fcntl.ioctl(fd.fileno(), req, arg)
                out.append((name, True, "ok"))
            except OSError as e:
                out.append((name, False, repr(e)))
    finally:
        fd.close()
    return out


def main(argv):
    ap = argparse.ArgumentParser(description="reset VT/console for SDL")
    ap.add_argument("--tty", default="/dev/tty0")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    ok = True
    for name, good, detail in reset(args.tty, args.dry_run):
        print("%s: %s (%s)" % (name, "OK" if good else "FAIL", detail))
        ok = ok and good
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
