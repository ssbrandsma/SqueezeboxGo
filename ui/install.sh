#!/bin/sh
# install.sh — stage UI-owned files into a rootfs overlay dir (DESTDIR-style).
#
# Installs, relative to DESTDIR:
#   <prefix>/bin/evdev2jive          input mapper daemon (from --bins)
#   <prefix>/bin/drm_splash           boot splash painter (from --bins)
#   <prefix>/bin/init-splash.sh       splash boot glue (this tree)
#   /etc/evdev2jive/rg35xxh.map       mapper config (this tree, --map to override)
#   <prefix>/share/jive/applets/RG35XXH*/  skins: *Applet.lua, *Meta.lua, images/
#   <prefix>/share/jive/fonts/FreeSans{,Bold}.ttf  (from --squeezeplay-src,
#                                     byte-identical to Agent 2's freefont target;
#                                     skipped with a warning when no src given)
#   /usr/share/squeezebox/splash_640x480.png  boot splash image (this tree)
#   <prefix>/share/squeezebox-ui-manifest.txt sha256 manifest of the above
#
# Usage:
#   ui/install.sh --destdir DIR [--prefix /opt/squeezeplay] [--bins DIR]
#                 [--squeezeplay-src DIR] [--map FILE] [--skin NAME]...
#
# --bins DIR must hold target-built `evdev2jive` + `drm_splash` (see
# ui/BRINGUP.md appendix for the cross-build commands). --skin may repeat;
# default is both RG35XXH skins. Exits nonzero on any missing input or
# failed post-install check. A manifest is always written into the overlay.
set -eu

HERE=$(dirname "$0")
PREFIX=/opt/squeezeplay
DESTDIR=
BINS=
SQ_SRC=
MAP=$HERE/input/rg35xxh.map
SKINS=

usage() {
    echo "usage: $0 --destdir DIR [--prefix P] [--bins DIR] [--squeezeplay-src DIR] [--map FILE] [--skin NAME]..." >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --destdir) DESTDIR=$2; shift 2 ;;
        --prefix) PREFIX=$2; shift 2 ;;
        --bins) BINS=$2; shift 2 ;;
        --squeezeplay-src) SQ_SRC=$2; shift 2 ;;
        --map) MAP=$2; shift 2 ;;
        --skin) SKINS="$SKINS $2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "unknown option: $1" >&2; usage ;;
    esac
done

[ -n "$DESTDIR" ] || { echo "install.sh: --destdir is required" >&2; usage; }
[ -z "$SKINS" ] && SKINS="RG35XXHBaseSkin RG35XXHLandscapeSkin"
case "$PREFIX" in /*) ;; *) echo "install.sh: --prefix must be absolute" >&2; exit 2 ;; esac

# --- validate inputs before writing anything ---
[ -n "$BINS" ] || { echo "install.sh: --bins DIR with target evdev2jive+drm_splash is required" >&2; exit 2; }
[ -x "$BINS/evdev2jive" ] || { echo "install.sh: missing executable $BINS/evdev2jive" >&2; exit 2; }
[ -x "$BINS/drm_splash" ] || { echo "install.sh: missing executable $BINS/drm_splash" >&2; exit 2; }
[ -f "$MAP" ] || { echo "install.sh: missing map $MAP" >&2; exit 2; }
# shellcheck disable=SC2086
for s in $SKINS; do
    [ -f "$HERE/skins/$s/${s}Applet.lua" ] || { echo "install.sh: missing skin $s Applet lua" >&2; exit 2; }
    [ -f "$HERE/skins/$s/${s}Meta.lua" ] || { echo "install.sh: missing skin $s Meta lua" >&2; exit 2; }
    [ -d "$HERE/skins/$s/images" ] || { echo "install.sh: missing skin $s images/" >&2; exit 2; }
done
[ -f "$HERE/splash/splash_640x480.png" ] || { echo "install.sh: missing splash png" >&2; exit 2; }
[ -f "$HERE/splash/init-splash.sh" ] || { echo "install.sh: missing init-splash.sh" >&2; exit 2; }

FONT_SRC_OK=0
if [ -n "$SQ_SRC" ]; then
    if [ -f "$SQ_SRC/dejavu-fonts-ttf-2.37/ttf/DejaVuSansCondensed.ttf" ] && \
       [ -f "$SQ_SRC/dejavu-fonts-ttf-2.37/ttf/DejaVuSansCondensed-Bold.ttf" ]; then
        FONT_SRC_OK=1
    else
        echo "install.sh: --squeezeplay-src lacks dejavu-fonts-ttf-2.37/ttf/*.ttf" >&2
        exit 2
    fi
else
    echo "install.sh: note: no --squeezeplay-src, skipping fonts (Agent 2 freefont target installs identical bytes)" >&2
fi

# --- install ---
BIN_D=$DESTDIR$PREFIX/bin
APPLETS_D=$DESTDIR$PREFIX/share/jive/applets
FONTS_D=$DESTDIR$PREFIX/share/jive/fonts
MAP_D=$DESTDIR/etc/evdev2jive
SPLASH_D=$DESTDIR/usr/share/squeezebox
mkdir -p "$BIN_D" "$APPLETS_D" "$MAP_D" "$SPLASH_D"
[ "$FONT_SRC_OK" -eq 1 ] && mkdir -p "$FONTS_D"

cp "$BINS/evdev2jive" "$BIN_D/evdev2jive"
cp "$BINS/drm_splash" "$BIN_D/drm_splash"
cp "$HERE/splash/init-splash.sh" "$BIN_D/init-splash.sh"
chmod 0755 "$BIN_D/evdev2jive" "$BIN_D/drm_splash" "$BIN_D/init-splash.sh"

cp "$MAP" "$MAP_D/rg35xxh.map"
chmod 0644 "$MAP_D/rg35xxh.map"

cp "$HERE/splash/splash_640x480.png" "$SPLASH_D/splash_640x480.png"
chmod 0644 "$SPLASH_D/splash_640x480.png"

# shellcheck disable=SC2086
for s in $SKINS; do
    rm -rf "${APPLETS_D:?}/$s"
    mkdir -p "$APPLETS_D/$s"
    cp "$HERE/skins/$s/${s}Applet.lua" "$HERE/skins/$s/${s}Meta.lua" "$APPLETS_D/$s/"
    cp -r "$HERE/skins/$s/images" "$APPLETS_D/$s/images"
    [ -f "$HERE/skins/$s/strings.txt" ] && cp "$HERE/skins/$s/strings.txt" "$APPLETS_D/$s/"
    find "$APPLETS_D/$s" -type d -exec chmod 0755 {} +
    find "$APPLETS_D/$s" -type f -exec chmod 0644 {} +
done

if [ "$FONT_SRC_OK" -eq 1 ]; then
    cp "$SQ_SRC/dejavu-fonts-ttf-2.37/ttf/DejaVuSansCondensed.ttf" "$FONTS_D/FreeSans.ttf"
    cp "$SQ_SRC/dejavu-fonts-ttf-2.37/ttf/DejaVuSansCondensed-Bold.ttf" "$FONTS_D/FreeSansBold.ttf"
    chmod 0644 "$FONTS_D/FreeSans.ttf" "$FONTS_D/FreeSansBold.ttf"
fi

# --- manifest (sorted, sha256 of every installed file) ---
MANIFEST=$DESTDIR$PREFIX/share/squeezebox-ui-manifest.txt
{
    echo "# squeezebox UI overlay manifest (ui/install.sh)"
    echo "# date-utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if git -C "$HERE" rev-parse --short HEAD >/dev/null 2>&1; then
        echo "# ui-commit: $(git -C "$HERE" rev-parse --short HEAD) ui-branch: $(git -C "$HERE" rev-parse --abbrev-ref HEAD)"
    fi
    echo "# prefix: $PREFIX"
    echo "# skins:$SKINS"
    if [ "$FONT_SRC_OK" -eq 1 ]; then
        echo "# fonts: FreeSans.ttf FreeSansBold.ttf (from squeezeplay dejavu 2.37)"
    else
        echo "# fonts: SKIPPED (no --squeezeplay-src)"
    fi
    _top=${PREFIX#/}; _top=${_top%%/*}
    ( cd "$DESTDIR" && find "$_top" etc usr -type f 2>/dev/null | grep -v 'squeezebox-ui-manifest\.txt\(\.tmp\)\?$' | sort -u | xargs sha256sum )
} >"$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"
chmod 0644 "$MANIFEST"

# --- post-install checks ---
fail=0
check() { [ -f "$DESTDIR$1" ] || { echo "install.sh: CHECK FAIL missing $1" >&2; fail=1; }; }
check "$PREFIX/bin/evdev2jive"
check "$PREFIX/bin/drm_splash"
check "$PREFIX/bin/init-splash.sh"
check "/etc/evdev2jive/rg35xxh.map"
check "/usr/share/squeezebox/splash_640x480.png"
# shellcheck disable=SC2086
for s in $SKINS; do
    check "$PREFIX/share/jive/applets/$s/${s}Applet.lua"
    check "$PREFIX/share/jive/applets/$s/${s}Meta.lua"
done
if [ "$FONT_SRC_OK" -eq 1 ]; then
    check "$PREFIX/share/jive/fonts/FreeSans.ttf"
    check "$PREFIX/share/jive/fonts/FreeSansBold.ttf"
fi
[ -x "$DESTDIR$PREFIX/bin/evdev2jive" ] || { echo "install.sh: CHECK FAIL evdev2jive not executable" >&2; fail=1; }
[ -x "$DESTDIR$PREFIX/bin/drm_splash" ] || { echo "install.sh: CHECK FAIL drm_splash not executable" >&2; fail=1; }
[ "$fail" -eq 0 ] || exit 1

n=$(grep -c -v '^#' "$MANIFEST")
echo "install.sh: staged $n files under $DESTDIR (manifest: $PREFIX/share/squeezebox-ui-manifest.txt)"
