#!/bin/sh
# build-native-deps.sh — host-arch prerequisites for NATIVE validation builds.
#
# The real target build runs in the pinned container (Dockerfile). This script
# prepares the single host dependency a NATIVE (x86_64) validation build needs
# beyond build-essential: ALSA headers + lib (Jive's own audio backend).
#
# Usage:
#   build-native-deps.sh --install            # apt install (needs root)
#   build-native-deps.sh [--prefix DIR]       # rootless: apt download + extract
#   eval "$(build-native-deps.sh --env [--prefix DIR])"   # export EXTRA_* flags
#
# Then run the native validation build:
#   make -f Makefile.linux-aarch64 CROSS_COMPILE= ARCHFLAGS="-march=x86-64" \
#       LUA_ARCHFLAGS="-s -O2"
#
# Rootless runtime note: prefix lib dir must be on LD_LIBRARY_PATH to EXECUTE
# the built jive binary (linking needs only -L, which --env provides).

set -eu

PREFIX="${HOME}/.cache/squeezeplay-native-deps"
MODE="fetch"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
    --install) MODE="install"; shift ;;
    --env) MODE="env"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ALSA_LIBDIR="$PREFIX/usr/lib/x86_64-linux-gnu"

case "$MODE" in
  install)
    if [ "$(id -u)" -ne 0 ]; then
      echo "ERROR: --install needs root; omit it for rootless mode" >&2
      exit 1
    fi
    apt-get update
    apt-get install -y --no-install-recommends libasound2-dev
    ;;
  fetch)
    mkdir -p "$PREFIX"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    (cd "$tmp" && apt-get download libasound2-dev libasound2t64)
    for d in "$tmp"/*.deb; do dpkg-deb -x "$d" "$PREFIX"; done
    [ -f "$PREFIX/usr/include/alsa/asoundlib.h" ] || \
      { echo "ERROR: asoundlib.h missing after extract" >&2; exit 1; }
    [ -e "$ALSA_LIBDIR/libasound.so" ] || \
      { echo "ERROR: libasound.so missing after extract" >&2; exit 1; }
    echo "native ALSA deps extracted to $PREFIX"
    echo "run: eval \"\$($0 --env --prefix $PREFIX)\""
    ;;
  env)
    if [ ! -f "$PREFIX/usr/include/alsa/asoundlib.h" ]; then
      echo "echo 'ERROR: $PREFIX has no ALSA headers; run without --env first' >&2; false"
      exit 0
    fi
    echo "export EXTRA_CFLAGS=\"-I$PREFIX/usr/include\""
    echo "export EXTRA_LDFLAGS=\"-L$ALSA_LIBDIR -Wl,-rpath,$ALSA_LIBDIR\""
    echo "export LD_LIBRARY_PATH=\"$ALSA_LIBDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
    ;;
esac
