#!/usr/bin/env bash
# build-kernel.sh — apply OOT patches + build Image/modules/DTBs for RG35XX H.
#
# Usage:
#   build-kernel.sh --src DIR --out DIR [--jobs N] [--dry-run]
#   build-kernel.sh --help
#
# Expects DIR from fetch.sh (linux-<ver>). Applies patches/series in order,
# merges config/linux-rg35xx-h-aarch64.conf onto defconfig, builds with the
# pinned cross toolchain. Heavy: full build takes a long time; use --dry-run
# to print the exact command plan without executing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/pins.env"

log() { printf 'build-kernel.sh: %s\n' "$*"; }
die() { printf 'build-kernel.sh: ERROR: %s\n' "$*" >&2; exit 1; }

SRC="" OUT="" JOBS="$(nproc 2>/dev/null || echo 4)" DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --src) SRC="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -n "$SRC" ] && [ -n "$OUT" ] || die "need --src DIR and --out DIR"
# Absolutize: INSTALL_MOD_PATH is resolved relative to the make -C dir otherwise.
SRC="$(realpath -m "$SRC")" OUT="$(realpath -m "$OUT")"
EPOCH="${SOURCE_DATE_EPOCH:-$SOURCE_DATE_EPOCH_DEFAULT}"
export SOURCE_DATE_EPOCH="$EPOCH"
export ARCH="$KARCH" CROSS_COMPILE="$KCROSS_COMPILE" KCFLAGS="$KCFLAGS"
# Pin the wall clock kbuild embeds in the UTS version string (scripts/mkversion
# uses `date` unless told otherwise, which made every Image unique). GNU date
# syntax; the pinned container and Ubuntu hosts both provide it.
if date -u -d "@$EPOCH" '+%a %b %d %H:%M:%S UTC %Y' >/dev/null 2>&1; then
    export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$EPOCH" '+%a %b %d %H:%M:%S UTC %Y')"
    export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-builder}"
    export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-repro}"
fi

run() { if [ "$DRY" = 1 ]; then printf '+ %s\n' "$*"; else log "$*"; "$@"; fi; }
[ -f "$SRC/Makefile" ] || die "no kernel tree at $SRC (run fetch.sh first)"
command -v "${KCROSS_COMPILE}gcc" >/dev/null 2>&1 || [ "$DRY" = 1 ] \
    || die "missing cross compiler ${KCROSS_COMPILE}gcc (use build/docker image)"

# 1. OOT patches (quilt-style series; patches live in kernel/patches/).
SERIES="$HERE/patches/series"
if [ -f "$SERIES" ]; then
    while IFS= read -r p || [ -n "$p" ]; do
        case "$p" in ''|'#'*) continue ;; esac
        [ -f "$HERE/patches/$p" ] || die "series lists missing patch: $p"
        if [ "$DRY" = 1 ]; then
            printf '+ patch -p1 -d %s < %s\n' "$SRC" "$HERE/patches/$p"
        else
            log "applying $p"
            patch -p1 -d "$SRC" --forward --no-backup-if-mismatch < "$HERE/patches/$p" \
                || die "patch failed: $p (see $HERE/patches/oot-patch-list.md)"
        fi
    done < "$SERIES"
else
    log "no patches/series; building pristine $LINUX_TAG (display will not work)"
fi

# 2. Config: defconfig + our fragment.
FRAG="$HERE/config/linux-rg35xx-h-aarch64.conf"
[ -f "$FRAG" ] || die "missing config fragment $FRAG"
run make -C "$SRC" defconfig
run bash -c "cat '$FRAG' >> '$SRC/.config'"
run make -C "$SRC" olddefconfig

# 3. Build.
run make -C "$SRC" -j"$JOBS" Image modules dtbs

# 4. Install to staging.
run mkdir -p "$OUT/boot" "$OUT/dtbs" "$OUT/modules"
run cp "$SRC/arch/arm64/boot/Image" "$OUT/boot/Image"
run cp "$SRC/arch/arm64/boot/dts/allwinner/sun50i-h700-anbernic-rg35xx-h.dtb" \
    "$OUT/dtbs/sun50i-h700-anbernic-rg35xx-h.dtb"
run make -C "$SRC" INSTALL_MOD_PATH="$OUT/modules" modules_install
run bash -c "cd '$OUT' && find boot dtbs -type f | sort | xargs sha256sum > SHA256SUMS.kernel"
log "kernel staging ready in $OUT (epoch $EPOCH)"
