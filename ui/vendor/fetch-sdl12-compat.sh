#!/bin/sh
# fetch-sdl12-compat.sh — download + verify the pinned sdl12-compat source.
#
# Usage: ./fetch-sdl12-compat.sh [DESTDIR]
#   DESTDIR defaults to /tmp/sdl12-compat-src. Prints the extracted dir.
# Never vendors the tree into git; the build unpacks from a verified tarball.
set -eu

HERE=$(dirname "$0")
# shellcheck disable=SC1091
. "$HERE/sdl12-compat.pin"

DEST=${1:-/tmp/sdl12-compat-src}
mkdir -p "$DEST"
TARBALL="$DEST/sdl12-compat-$TAG.tar.gz"

if [ ! -f "$TARBALL" ]; then
    curl -fsSL -o "$TARBALL" "$TARBALL_URL"
fi

echo "$TARBALL_SHA256  $TARBALL" | sha256sum -c - >/dev/null \
    || { echo "sha256 MISMATCH for $TARBALL" >&2; exit 1; }

tar xzf "$TARBALL" -C "$DEST"
echo "$DEST/sdl12-compat-$TAG"
