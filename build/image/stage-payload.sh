#!/usr/bin/env bash
# stage-payload.sh — layer the Squeezebox payload onto a rootfs staging tree.
#
# Usage:
#   stage-payload.sh --staging DIR --core-tgz FILE --uibins DIR --sdl2 DIR
#                    --compat DIR --bsp-so FILE --squeezeplay-src DIR
#                    --kernel-modules DIR --target-libs FILE [--epoch EPOCH]
#
# Inputs:
#   --staging DIR        mkrootfs.sh output dir (layers on top, idempotent)
#   --core-tgz FILE      Agent-2 squeezeplay-aarch64-*.tgz (opt/ subtree)
#   --uibins DIR         target evdev2jive + drm_splash (+ sdl_smoke, optional)
#   --sdl2 DIR           kmsdrm SDL2 install prefix (lib/libSDL2-2.0.so.0)
#   --compat DIR         sdl12-compat install prefix (lib/libSDL-1.2.so.0)
#   --bsp-so FILE        built rg35xxh_bsp.so (Lua C module, aarch64)
#   --squeezeplay-src DIR
#                        pinned squeezeplay src/ (DejaVu fonts for ui overlay)
#   --kernel-modules DIR build-kernel.sh .../modules (lib/modules/<ver>)
#   --target-libs FILE   closure list "SONAME<tab>HOSTPATH" (see closure.py),
#                        installed to /usr/lib/aarch64-linux-gnu
#   --epoch EPOCH        clamp new-file mtimes (default: $SOURCE_DATE_EPOCH)
#
# Steps: core extract + dev prune + SDL2/compat shadow + ui/install.sh overlay
# + asound.conf + audio-owner + standalone tree (ship-disabled) + BSP applet
# + kernel modules + target lib closure + manifests. Runs unprivileged.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

log() { printf 'stage-payload.sh: %s\n' "$*"; }
die() { printf 'stage-payload.sh: ERROR: %s\n' "$*" >&2; exit 1; }

STAGING="" CORE="" UIBINS="" SDL2="" COMPAT="" BSPSO="" SQSRC="" KMOD="" TLIBS=""
EPOCH="${SOURCE_DATE_EPOCH:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --staging) STAGING="$2"; shift 2 ;;
        --core-tgz) CORE="$2"; shift 2 ;;
        --uibins) UIBINS="$2"; shift 2 ;;
        --sdl2) SDL2="$2"; shift 2 ;;
        --compat) COMPAT="$2"; shift 2 ;;
        --bsp-so) BSPSO="$2"; shift 2 ;;
        --squeezeplay-src) SQSRC="$2"; shift 2 ;;
        --kernel-modules) KMOD="$2"; shift 2 ;;
        --target-libs) TLIBS="$2"; shift 2 ;;
        --epoch) EPOCH="$2"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -n "$STAGING" ] && [ -n "$CORE" ] && [ -n "$UIBINS" ] && [ -n "$SDL2" ] \
&& [ -n "$COMPAT" ] && [ -n "$BSPSO" ] && [ -n "$SQSRC" ] \
&& [ -n "$KMOD" ] && [ -n "$TLIBS" ] || die "missing required args (see --help)"
[ -d "$STAGING/etc" ] || die "no mkrootfs staging at $STAGING"
[ -f "$CORE" ] || die "missing core tarball $CORE"
[ -x "$UIBINS/evdev2jive" ] && [ -x "$UIBINS/drm_splash" ] \
    || die "uibins lack target evdev2jive+drm_splash"
[ -f "$SDL2/lib/libSDL2-2.0.so.0" ] || die "missing $SDL2/lib/libSDL2-2.0.so.0"
[ -f "$COMPAT/lib/libSDL-1.2.so.0" ] || die "missing $COMPAT/lib/libSDL-1.2.so.0"
[ -f "$BSPSO" ] || die "missing BSP module $BSPSO"
[ -d "$KMOD/lib/modules" ] || die "missing $KMOD/lib/modules"
[ -f "$TLIBS" ] || die "missing target-libs list $TLIBS"

PREFIX=/opt/squeezeplay
SP="$STAGING$PREFIX"

# 1. Core tree (Agent 2 staging, tarred as opt/; overwrites older payload).
tar -xzf "$CORE" -C "$STAGING"
[ -x "$SP/bin/jive" ] || die "core tarball lacks $PREFIX/bin/jive"
log "core extracted: $(tar -tzf "$CORE" | wc -l) members"

# 2. Prune build-time payload (INSTALL-LAYOUT.md "PRUNE on the image").
rm -rf "$SP/include" "$SP/man" "$SP/share/man" "$SP/share/doc" "$SP/share/aclocal"
rm -f "$SP"/bin/sdl-config "$SP"/bin/*-config \
    "$SP"/bin/cjpeg "$SP"/bin/djpeg "$SP"/bin/jpegtran \
    "$SP"/bin/rdjpgcom "$SP"/bin/wrjpgcom "$SP"/bin/xmlwf \
    "$SP"/bin/freetype-config
rm -f "$SP"/lib/*.a "$SP"/lib/*.la
# Keep only SONAME symlinks + real versioned files (drop unversioned .so).
for devlink in "$SP"/lib/*.so; do
    [ -L "$devlink" ] && rm -f "$devlink" || true
done
[ -e "$SP/lib/libSDL.so" ] && rm -f "$SP/lib/libSDL.so" || true
log "dev payload pruned"

# 3. SDL stack: kmsdrm SDL2 + sdl12-compat shadow the build-ABI libSDL-1.2.
# The build-ABI libSDL (dummy video, link-only) is useless on target; the
# compat lib carries the same SONAME and dlopen()s the local SDL2 at runtime
# (resolved via LD_LIBRARY_PATH=$PREFIX/lib, see services/squeezeplay.sh).
rm -f "$SP"/lib/libSDL-1.2.so.0.11.4 "$SP"/lib/libSDL-1.2.so.0
cp -L "$COMPAT/lib/libSDL-1.2.so.0" "$SP/lib/libSDL-1.2.so.1.2.78"
ln -sf libSDL-1.2.so.1.2.78 "$SP/lib/libSDL-1.2.so.0"
cp -L "$SDL2/lib/libSDL2-2.0.so.0" "$SP/lib/libSDL2-2.0.so.0.3200.10"
ln -sf libSDL2-2.0.so.0.3200.10 "$SP/lib/libSDL2-2.0.so.0"
chmod 0644 "$SP"/lib/libSDL-1.2.so.1.2.78 "$SP"/lib/libSDL2-2.0.so.0.3200.10
log "SDL stack installed (compat 1.2.78 + SDL2 2.32.10 kmsdrm)"

# 4. UI overlay (Agent 4): bins + skins + map + splash + fonts + manifest.
# Staged to an empty overlay dir first: ui/install.sh manifests everything
# under its DESTDIR, so staging straight into $STAGING would misattribute
# the whole core tree to the UI manifest. Merged after (DESTDIR design).
UIOVL="$(mktemp -d)"
trap 'rm -rf "$UIOVL"' EXIT
sh "$REPO_ROOT/ui/install.sh" --destdir "$UIOVL" --prefix "$PREFIX" \
    --bins "$UIBINS" --squeezeplay-src "$SQSRC"
if [ "$EPOCH" != "0" ]; then
    sed -i "s/^# date-utc: .*/# date-utc: $(date -u -d "@$EPOCH" '+%Y-%m-%dT%H:%M:%SZ')/" \
        "$UIOVL$PREFIX/share/squeezebox-ui-manifest.txt"
fi
cp -a "$UIOVL"/. "$STAGING"/
rm -rf "$UIOVL"
trap - EXIT
log "ui overlay staged"

# 5. Audio (Agent 3): asound.conf + arbiter. No enables (not a unit).
install -m 0644 "$REPO_ROOT/audio/alsa/asound.conf" "$STAGING/etc/asound.conf"
install -m 0755 "$REPO_ROOT/audio/arbiter/audio-owner" "$STAGING/usr/sbin/audio-owner"
log "audio payload staged"

# 6. Standalone (Agent 5): code under /usr/lib, per-source conf under /etc.
# Ship DISABLED: units installed, nothing enabled (backends UNIMPLEMENTED).
mkdir -p "$STAGING/usr/lib/squeezebox/standalone/base" \
    "$STAGING/usr/lib/squeezebox/standalone/integration"
install -m 0755 "$REPO_ROOT"/standalone/base/*.sh \
    "$STAGING/usr/lib/squeezebox/standalone/base/"
install -m 0755 "$REPO_ROOT"/standalone/integration/*.sh \
    "$STAGING/usr/lib/squeezebox/standalone/integration/"
install -m 0644 "$REPO_ROOT"/standalone/integration/*.lua \
    "$STAGING/usr/lib/squeezebox/standalone/integration/"
for svc in "$REPO_ROOT"/standalone/integration/services/*/; do
    id="$(basename "$svc")"
    mkdir -p "$STAGING/etc/squeezebox/standalone/services/$id"
    install -m 0644 "$svc"/*.conf \
        "$STAGING/etc/squeezebox/standalone/services/$id/"
done
install -m 0644 "$REPO_ROOT"/standalone/systemd/overlay/usr/lib/systemd/system/* \
    "$STAGING/usr/lib/systemd/system/"
log "standalone staged (disabled: no wants symlinks)"

# 7. BSP applet + Lua C module (Agent 2 rg35xxh_bsp tree).
BSPAPP="$SP/share/jive/applets/SqueezeboxRG35XXH"
rm -rf "$BSPAPP" && mkdir -p "$BSPAPP"
cp "$REPO_ROOT"/squeezeplay/configuration/rg35xxh_bsp/share/applets/SqueezeboxRG35XXH/* \
    "$BSPAPP/"
chmod 0644 "$BSPAPP"/*
install -m 0644 "$BSPSO" "$SP/lib/lua/5.1/rg35xxh_bsp.so"
log "BSP applet + module staged"

# 8. Kernel modules (wifi needs rtw88_8821cs.ko).
mkdir -p "$STAGING/lib/modules"
cp -a "$KMOD"/lib/modules/. "$STAGING/lib/modules/"
log "kernel modules staged"

# 9. Target runtime lib closure (noble arm64 debs + ALSA + zlib; no glibc).
# When a base userland is staged underneath (stage-userland.sh), its
# dpkg-managed libs win: any SONAME already present is KEPT and the closure
# copy is skipped (logged + recorded in the manifest below). Skeleton-only
# staging (no userland) behaves exactly as before: nothing is skipped.
LIBD="$STAGING/usr/lib/aarch64-linux-gnu"
mkdir -p "$LIBD"
SKIPPED_LIBS=""
while IFS="$(printf '\t')" read -r soname hostpath _rest; do
    case "$soname" in ''|'#'*) continue ;; esac
    if [ -e "$LIBD/$soname" ]; then
        SKIPPED_LIBS="$SKIPPED_LIBS $soname"
        log "target lib $soname: kept userland version (closure copy skipped)"
        continue
    fi
    [ -f "$hostpath" ] || die "closure host lib missing: $soname <- $hostpath"
    cp -L "$hostpath" "$LIBD/$soname"
    chmod 0644 "$LIBD/$soname"
done < "$TLIBS"
log "target libs staged ($(ls "$LIBD" | wc -l) files)"
[ -n "$SKIPPED_LIBS" ] && log "userland-provided libs kept:$SKIPPED_LIBS"

# 10. aarch64 smoke binary (ui/BRINGUP.md section 2 ships it on the image).
[ -x "$UIBINS/sdl_smoke" ] && install -m 0755 "$UIBINS/sdl_smoke" "$SP/bin/sdl_smoke" \
    || log "note: no sdl_smoke in uibins, skipped"

# 11. Payload manifest (component versions + shas for the release record).
{
    echo "# squeezebox payload manifest (build/image/stage-payload.sh)"
    echo "# epoch: $EPOCH"
    echo "core-tarball: $(basename "$CORE") $(sha256sum "$CORE" | awk '{print $1}')"
    echo "core-jive: $(sha256sum "$SP/bin/jive" | awk '{print $1}')"
    echo "core-jive_alsa: $(sha256sum "$SP/bin/jive_alsa" | awk '{print $1}')"
    echo "sdl2-kmsdrm: $(sha256sum "$SP/lib/libSDL2-2.0.so.0.3200.10" | awk '{print $1}')"
    echo "sdl12-compat: $(sha256sum "$SP/lib/libSDL-1.2.so.1.2.78" | awk '{print $1}')"
    echo "evdev2jive: $(sha256sum "$SP/bin/evdev2jive" | awk '{print $1}')"
    echo "drm_splash: $(sha256sum "$SP/bin/drm_splash" | awk '{print $1}')"
    echo "bsp-module: $(sha256sum "$SP/lib/lua/5.1/rg35xxh_bsp.so" | awk '{print $1}')"
    echo "asound.conf: $(sha256sum "$STAGING/etc/asound.conf" | awk '{print $1}')"
    echo "audio-owner: $(sha256sum "$STAGING/usr/sbin/audio-owner" | awk '{print $1}')"
    if [ -n "$SKIPPED_LIBS" ]; then
        echo "userland-libs-kept:$SKIPPED_LIBS"
        for s in $SKIPPED_LIBS; do
            echo "userland-lib-sha: $s $(sha256sum "$LIBD/$s" | awk '{print $1}')"
        done
    else
        echo "userland-libs-kept: (none — skeleton-only staging)"
    fi
} > "$STAGING/payload-manifest.txt"
chmod 0644 "$STAGING/payload-manifest.txt"

# 12. Epoch clamp + manifests (mkrootfs.sh format; payload files are new).
if [ "$EPOCH" != "0" ]; then
    find "$STAGING" -exec touch -h -d "@$EPOCH" {} +
fi
(cd "$STAGING" && find . -mindepth 1 ! -name 'manifest.*' -printf '%M %p\n' | sort > manifest.modes)
(cd "$STAGING" && find . -type f ! -name 'manifest.*' | sort | xargs sha256sum > manifest.sha256)
if [ "$EPOCH" != "0" ]; then
    touch -h -d "@$EPOCH" "$STAGING/manifest.modes" "$STAGING/manifest.sha256"
fi
log "payload ready: $STAGING ($(wc -l < "$STAGING/manifest.sha256") files)"