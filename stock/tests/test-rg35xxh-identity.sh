#!/usr/bin/env bash
# test-rg35xxh-identity.sh — the rg35xxh platform identity patch is
# present, internally consistent, and its applet-target fallback
# behaves (rg35xxh first, baby fallback, squeezenetwork last).
set -u
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$ROOT"
PATCH="stock/bundle/rg35xxh-identity.patch"
MIRROR="stock/tests/applet_target_fallback_test.lua"
fail=0

marker() { # marker <file> <fixed-string>
  if grep -qF "$2" "$1"; then
    echo "IDENT PASS: [$1] $2"
  else
    echo "IDENT FAIL: [$1] missing: $2"
    fail=1
  fi
}

[ -f "$PATCH" ] || { echo "IDENT FAIL: $PATCH missing"; exit 1; }

# patch contents: machine + player type + query target + fallback
marker "$PATCH" 'machine = "rg35xxh"'
marker "$PATCH" 'setDeviceType("rg35xxh", "Squeezebox RG35XX H")'
marker "$PATCH" 'target = target or "rg35xxh"'
marker "$PATCH" 'falling back to baby'
marker "$PATCH" 'triedBaby'

# mirror coupling: behavior test tracks the same logic
marker "$MIRROR" 'target = target or "rg35xxh"'
marker "$MIRROR" 'falling back to baby'
marker "$MIRROR" 'triedBaby'

# behavior
if command -v lua5.1 >/dev/null 2>&1; then
  if lua5.1 "$MIRROR"; then
    echo "IDENT PASS: fallback behavior"
  else
    echo "IDENT FAIL: fallback behavior"
    fail=1
  fi
else
  echo "IDENT FAIL: lua5.1 not installed (behavior unverified)"
  fail=1
fi

exit "$fail"
