#!/usr/bin/env bash
# pack.sh — reproducible SqueezeboxGo App Center ZIP builder (host-only).
#
# Builds SqueezeboxGo-<ver>-stockos-rg35xxh.zip from:
#   repo      this tree (entry script, lifecycle scripts, icon generator,
#             BSP applet overlay) + ui/skins/RG35XXHBaseSkin overlay (read-only
#             packaging use; Agent 4's tree is never modified)
#   Jammy tarball  aarch64 squeezeplay build (glibc <= 2.35)
#   fbcon SDL      stock-kernel framebuffer libSDL shadowing the dummy one
#   icon      generated at pack time (git stays text-only)
#
# ZIP layout (merge APPS/ into the card's Roms/):
#   APPS/SqueezeboxGo.sh                 FAT entry (POSIX sh)
#   APPS/Imgs/SqueezeboxGo.png           240x180 RGBA icon (device truth)
#   APPS/SqueezeboxGo/VERSION            payload version
#   APPS/SqueezeboxGo/SHA256SUMS         payload.tar.gz hash (entry verifies)
#   APPS/SqueezeboxGo/payload.tar.gz     ext4 runtime (jive/ + lib-fbcon/ +
#                                        launch.sh + restore.sh + config/)
#
# Reproducible: fixed mtime (see --epoch), sorted entries, fixed
# uid/gid/modes, gzip -n. Building twice yields identical bytes.
#
# Usage:
#   squeezebox-go/pack.sh [--output DIR] [--version VER]
#     [--jammy-tarball PATH] [--fbcon-lib PATH] [--fixture] [--epoch E]
#
# Defaults: --output squeezebox-go/dist, --version from VERSION file,
#   artifacts from $JAMMY_TARBALL / $FBCON_LIB or the known /tmp paths.
#   --fixture builds a tiny synthetic payload (for host tests when the
#   real aarch64 artifacts are absent; the ZIP is clearly marked so it
#   can never be mistaken for a device build).
#
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"; then
	REPO="$ROOT"
else
	REPO="$(cd "$HERE/../.." && pwd)"
fi

OUT_DIR="$HERE/dist"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null | tr -d '[:space:]')"
JAMMY="${JAMMY_TARBALL:-/tmp/jammy-sp/squeezeplay/squeezeplay-aarch64-9.0.0.tgz}"
FBCON="${FBCON_LIB:-/tmp/sdl-fbcon/out/lib/libSDL-1.2.so.0.11.4}"
FIXTURE=0
EPOCH=''

while [ $# -gt 0 ]; do
	case "$1" in
		--output) OUT_DIR="${2:-}"; shift 2 ;;
		--output=*) OUT_DIR="${1#--output=}"; shift ;;
		--version) VERSION="${2:-}"; shift 2 ;;
		--version=*) VERSION="${1#--version=}"; shift ;;
		--jammy-tarball) JAMMY="${2:-}"; shift 2 ;;
		--jammy-tarball=*) JAMMY="${1#--jammy-tarball=}"; shift ;;
		--fbcon-lib) FBCON="${2:-}"; shift 2 ;;
		--fbcon-lib=*) FBCON="${1#--fbcon-lib=}"; shift ;;
		--fixture) FIXTURE=1; shift ;;
		--epoch) EPOCH="${2:-}"; shift 2 ;;
		--epoch=*) EPOCH="${1#--epoch=}"; shift ;;
		-h|--help) sed -n '2,32p' "$0"; exit 0 ;;
		*) printf 'pack.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
	esac
done

[ -n "$VERSION" ] || { printf 'pack.sh: no version (VERSION file missing?)\n' >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { printf 'pack.sh: python3 required\n' >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { printf 'pack.sh: tar required\n' >&2; exit 2; }
command -v gzip >/dev/null 2>&1 || { printf 'pack.sh: gzip required\n' >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { printf 'pack.sh: sha256sum required\n' >&2; exit 2; }

# Mtime source: CLI > SOURCE_DATE_EPOCH > last commit time > fixed fallback.
if [ -z "$EPOCH" ]; then
	if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
		EPOCH="$SOURCE_DATE_EPOCH"
	elif git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		EPOCH="$(git -C "$REPO" log -1 --format=%ct 2>/dev/null || echo '')"
	fi
fi
[ -n "$EPOCH" ] || EPOCH=1767225600  # 2026-01-01T00:00:00Z
case "$EPOCH" in ''|*[!0-9]*) printf 'pack.sh: bad epoch: %s\n' "$EPOCH" >&2; exit 2 ;; esac

APPLET_SRC="$REPO/squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH"
SKIN_SRC="$REPO/ui/skins/RG35XXHBaseSkin"
for d in "$APPLET_SRC" "$SKIN_SRC"; do
	[ -d "$d" ] || { printf 'pack.sh: missing overlay source: %s\n' "$d" >&2; exit 2; }
done

if [ "$FIXTURE" = '1' ]; then
	MODE='fixture'
	JAMMY_SHA='fixture'
	FBCON_SHA='fixture'
else
	MODE='device'
	[ -f "$JAMMY" ] || { printf 'pack.sh: Jammy tarball not found: %s\n' "$JAMMY" >&2
		printf '  (build per docs/test-results/diag-jammy-build.md, or pass --fixture)\n' >&2; exit 2; }
	[ -f "$FBCON" ] || { printf 'pack.sh: fbcon libSDL not found: %s\n' "$FBCON" >&2
		printf '  (build per docs/test-results/sdl-fbcon-build.md, or pass --fixture)\n' >&2; exit 2; }
	JAMMY_SHA="$(sha256sum "$JAMMY" | cut -d' ' -f1)"
	FBCON_SHA="$(sha256sum "$FBCON" | cut -d' ' -f1)"
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PAY="$STAGE/payroot"
ZIPROOT="$STAGE/ziproot"
mkdir -p "$PAY" "$ZIPROOT/APPS/SqueezeboxGo" "$ZIPROOT/APPS/Imgs"

printf 'pack.sh: mode=%s version=%s epoch=%s\n' "$MODE" "$VERSION" "$EPOCH"

# --- payload tree ---------------------------------------------------------
if [ "$FIXTURE" = '1' ]; then
	mkdir -p "$PAY/jive/bin" "$PAY/jive/lib" "$PAY/jive/share/jive/applets"
	printf '#!/bin/sh\necho "fixture jive (packaging test only)"\nexit 42\n' >"$PAY/jive/bin/jive"
	chmod +x "$PAY/jive/bin/jive"
	mkdir -p "$PAY/lib-fbcon"
	printf 'fixture libSDL (packaging test only)\n' >"$PAY/lib-fbcon/libSDL-1.2.so.0"
else
	mkdir -p "$PAY/jive"
	tar -xzf "$JAMMY" -C "$PAY/jive" --strip-components=2 'opt/squeezeplay'
	mkdir -p "$PAY/lib-fbcon"
	cp "$FBCON" "$PAY/lib-fbcon/libSDL-1.2.so.0"
fi
# Repo overlays (read-only copies; source trees untouched).
mkdir -p "$PAY/jive/share/jive/applets"
cp -r "$APPLET_SRC" "$PAY/jive/share/jive/applets/SqueezeboxRG35XXH"
cp -r "$SKIN_SRC" "$PAY/jive/share/jive/applets/RG35XXHBaseSkin"
# Prune overlay junk that must never ship (editor backups, if any).
find "$PAY/jive/share/jive/applets/SqueezeboxRG35XXH" "$PAY/jive/share/jive/applets/RG35XXHBaseSkin" \
	\( -name '*~' -o -name '.DS_Store' \) -delete 2>/dev/null || true

cp "$HERE/runtime/launch.sh" "$HERE/runtime/restore.sh" "$PAY/"
printf '%s\n' "$VERSION" >"$PAY/VERSION"
mkdir -p "$PAY/config"
{
	printf 'SqueezeboxGo payload manifest\n'
	printf 'version: %s\n' "$VERSION"
	printf 'mode: %s\n' "$MODE"
	printf 'epoch: %s\n' "$EPOCH"
	printf 'jammy_tarball_sha256: %s\n' "$JAMMY_SHA"
	printf 'fbcon_libsha256: %s\n' "$FBCON_SHA"
} >"$PAY/MANIFEST"

# Fixed modes for reproducibility (FAT transit ignores them, but the
# ext4 extract + rebuild-twice comparison need them stable).
find "$PAY" -type d -exec chmod 755 {} +
find "$PAY" -type f -exec chmod 644 {} +
chmod 755 "$PAY/launch.sh" "$PAY/restore.sh"
[ -f "$PAY/jive/bin/jive" ] && chmod 755 "$PAY/jive/bin/jive"

# --- payload.tar.gz (ordered top level, sorted, fixed meta, gzip -n) ------
(cd "$PAY" && tar --sort=name --mtime="@$EPOCH" --owner=0 --group=0 \
	--numeric-owner -cf - MANIFEST VERSION config jive launch.sh lib-fbcon restore.sh \
	| gzip -n >"$ZIPROOT/APPS/SqueezeboxGo/payload.tar.gz")

# --- FAT part --------------------------------------------------------------
cp "$HERE/apps/SqueezeboxGo.sh" "$ZIPROOT/APPS/SqueezeboxGo.sh"
python3 "$HERE/icon/make-icon.py" -o "$ZIPROOT/APPS/Imgs/SqueezeboxGo.png"
printf '%s\n' "$VERSION" >"$ZIPROOT/APPS/SqueezeboxGo/VERSION"
(cd "$ZIPROOT/APPS/SqueezeboxGo" && sha256sum payload.tar.gz >SHA256SUMS)

# --- outer ZIP (stdlib zipfile: fixed dates, sorted, stable perms) ---------
ZIP_NAME="SqueezeboxGo-$VERSION-stockos-rg35xxh.zip"
[ "$FIXTURE" = '1' ] && ZIP_NAME="SqueezeboxGo-$VERSION-fixture.zip"
mkdir -p "$OUT_DIR"
OUT_ZIP="$OUT_DIR/$ZIP_NAME"
python3 - "$EPOCH" "$ZIPROOT" "$OUT_ZIP" <<'EOF'
import os, sys, zipfile
epoch, root, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
import datetime
dt = datetime.datetime.fromtimestamp(max(epoch, 315532800),
                                     tz=datetime.timezone.utc).replace(tzinfo=None)  # clamp >= 1980
names = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for fn in sorted(filenames):
        p = os.path.join(dirpath, fn)
        names.append(os.path.relpath(p, root))
names.sort()
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for name in names:
        zi = zipfile.ZipInfo(name, date_time=dt.timetuple()[:6])
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.create_system = 3  # unix
        mode = 0o755 if name.endswith(".sh") else 0o644
        zi.external_attr = (mode & 0xFFFF) << 16
        with open(os.path.join(root, name), "rb") as f:
            z.writestr(zi, f.read())
EOF
(cd "$OUT_DIR" && sha256sum "$ZIP_NAME" >"$ZIP_NAME.sha256")

ZIP_SHA="$(cut -d' ' -f1 <"$OUT_ZIP.sha256")"
ZIP_BYTES="$(wc -c <"$OUT_ZIP")"
printf 'pack.sh: wrote %s (%s bytes, sha256 %s)\n' "$OUT_ZIP" "$ZIP_BYTES" "$ZIP_SHA"
printf 'pack.sh: payload jammy=%s fbcon=%s\n' "$JAMMY_SHA" "$FBCON_SHA"
