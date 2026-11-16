#!/usr/bin/env bash
# install-squeezebox-go.sh — install the SqueezeboxGo App Center entry.
#
# Additive-only: creates /opt/squeezebox-go (ext4 runtime) +
# /mnt/mmc/Roms/APPS/SqueezeboxGo.sh + Imgs/SqueezeboxGo.png (provisional
# icon — GO-APP final art overwrites it). Modifies ZERO stock files.
# Reversible via uninstall-squeezebox-go.sh.
#
# Usage (on device, as root):
#   bash install-squeezebox-go.sh --tarball <jammy.tgz> --sdl <libSDL.so> [--yes] [--dry-run]
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

GO_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$GO_SRC/../bundle/lib-safety.sh"

WANT_TGZ='673ec5eec78ca5127d7202951d292b194f47bc22747c9a12a8f82069bcc02baa'
WANT_SDL='3924a6254c1c4c9690b7d7f3905465b84f7dd134b372155909eca02d6f3f8d4a'
RUNTIME='/opt/squeezebox-go'
APPS_SH='/mnt/mmc/Roms/APPS/SqueezeboxGo.sh'
APPS_PNG='/mnt/mmc/Roms/APPS/Imgs/SqueezeboxGo.png'

TARBALL=''; SDL_LIB=''; DRY_RUN=0
while [ $# -gt 0 ]; do
	case "$1" in
		--tarball) TARBALL="${2:-}"; [ -n "$TARBALL" ] || fatal '--tarball needs a value'; shift 2 ;;
		--tarball=*) TARBALL="${1#--tarball=}"; shift ;;
		--sdl) SDL_LIB="${2:-}"; [ -n "$SDL_LIB" ] || fatal '--sdl needs a value'; shift 2 ;;
		--sdl=*) SDL_LIB="${1#--sdl=}"; shift ;;
		--yes) STOCK_YES=1; export STOCK_YES; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help)
			printf 'usage: %s --tarball <jammy.tgz> --sdl <libSDL-1.2.so.0.11.4> [--yes] [--dry-run]\n' "$0"
			exit 0 ;;
		*) fatal "unknown argument: $1 (see --help)" ;;
	esac
done

[ "$(id -u)" = '0' ] || fatal 'must run as root (APPS entries + /opt are root-owned)'
[ -n "$TARBALL" ] || fatal '--tarball is required (Jammy squeezeplay tarball)'
[ -n "$SDL_LIB" ] || fatal '--sdl is required (fbcon libSDL-1.2.so.0.11.4)'
[ -f "$TARBALL" ] || fatal "tarball not found: $TARBALL"
[ -f "$SDL_LIB" ] || fatal "SDL lib not found: $SDL_LIB"
[ -d /mnt/mmc/Roms/APPS ] || fatal 'TF1 APPS dir missing: /mnt/mmc/Roms/APPS (wrong card?)'

sha_of() { sha256sum "$1" | awk '{print $1}'; }
[ "$(sha_of "$TARBALL")" = "$WANT_TGZ" ] || fatal "tarball SHA mismatch (want $WANT_TGZ)"
[ "$(sha_of "$SDL_LIB")" = "$WANT_SDL" ] || fatal "SDL lib SHA mismatch (want $WANT_SDL)"

plan "install SqueezeboxGo (App Center, additive-only)" \
	"runtime:  $RUNTIME (tarball + fbcon SDL shadow)" \
	"entry:    $APPS_SH" \
	"icon:     $APPS_PNG (PROVISIONAL 240x180 art)" \
	"stock modifications: NONE" \
	"undo:     bash $GO_SRC/uninstall-squeezebox-go.sh --yes"

if [ "$DRY_RUN" = '1' ]; then
	note 'dry run: nothing installed.'
	exit 0
fi
confirm "Install SqueezeboxGo to $RUNTIME + APPS entry?"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
tar -xzf "$TARBALL" -C "$STAGE"
APP_TREE="$(dirname "$(find "$STAGE" -path '*bin/jive' -type f | head -n 1)")"
[ -n "$APP_TREE" ] && [ "$APP_TREE" != '.' ] || fatal 'tarball has no bin/jive'
APP_TREE="$(dirname "$APP_TREE")"

mkdir -p "$RUNTIME/libexec" "$RUNTIME/logs" "$RUNTIME/home"
rm -rf "$RUNTIME/app"
cp -a "$APP_TREE" "$RUNTIME/app"
cp -aL "$SDL_LIB" "$RUNTIME/libexec/libSDL-1.2.so.0"
chown -R root:root "$RUNTIME"
cat >"$RUNTIME/VERSION" <<EOF
SqueezeboxGo runtime (installed $(date -u +%Y-%m-%dT%H:%M:%SZ))
jammy-tarball-sha256: $WANT_TGZ
fbcon-libSDL-sha256: $WANT_SDL
jive: 9.0.0 r541 (Jammy-compatible)
EOF

cat >"$APPS_SH" <<'EOF'
#!/bin/bash
# SqueezeboxGo.sh — App Center entry for SqueezeboxGo (GO-HW install).
# Pattern mirrors stock APPS launchers; runtime lives on ext4 (Roms is VFAT).
RUNTIME="/opt/squeezebox-go"
LOG_FILE="$RUNTIME/logs/jive.log"

export HOME="$RUNTIME/home"
export SQUEEZEBOX_GO=1
export LD_LIBRARY_PATH="$RUNTIME/libexec:$RUNTIME/app/lib"
export SDL_VIDEODRIVER=fbcon
export SDL_FBDEV=/dev/fb0
export SDL_AUDIODRIVER=alsa

cd "$RUNTIME/app/bin" || exit 1
[ -f /mnt/mod/ctrl/volumeCtrl.dge ] && /mnt/mod/ctrl/volumeCtrl.dge &

./jive >"$LOG_FILE" 2>&1
rc=$?
kill -9 $(pidof volumeCtrl.dge) 2>/dev/null
exit $rc
EOF

python3 - "$APPS_PNG" <<'EOF'
import struct, sys, zlib
W, H = 240, 180  # PROVISIONAL art — GO-APP final icon overwrites this file
def px(x, y):
    border = x < 6 or y < 6 or x >= W - 6 or y >= H - 6
    return (90, 140, 255, 255) if border else (16, 32, 96, 255)
raw = b"".join(b"\x00" + b"".join(bytes(px(x, y)) for x in range(W)) for y in range(H))
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
EOF

note 'verifying...'
bash -n "$APPS_SH" || fatal 'entry script syntax check failed'
LD_LIBRARY_PATH="$RUNTIME/libexec:$RUNTIME/app/lib" ldd "$RUNTIME/app/bin/jive" 2>&1 | grep -q 'not found' \
	&& fatal 'jive has unresolved libs' || true
[ "$(sha_of "$RUNTIME/libexec/libSDL-1.2.so.0")" = "$WANT_SDL" ] || fatal 'installed SDL SHA drift'
file "$APPS_PNG" | grep -q '240 x 180' || fatal 'icon is not 240x180'
note "installed: $RUNTIME ($(du -sh "$RUNTIME" | cut -f1)) + APPS entry + provisional icon"
note 'menu launch: pick SqueezeboxGo in App Center (dmenu must be alive).'
note 'SSH-direct test MUST stop the frontend first: systemctl stop launcher.service'
