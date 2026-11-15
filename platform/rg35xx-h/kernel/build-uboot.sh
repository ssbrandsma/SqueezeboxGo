#!/usr/bin/env bash
# build-uboot.sh — build ATF BL31 + U-Boot SPL+SIT for RG35XX H, both DRAM variants.
#
# Usage:
#   build-uboot.sh --uboot DIR --atf DIR --out DIR [--variant ddr3|ddr4|both]
#                  [--jobs N] [--dry-run]
#
# Variants (WP0: units ship with DDR3 or LPDDR4; ID method TBD on hardware):
#   ddr4 = $UBOOT_DEFCONFIG as-is (SUNXI_DRAM_H616_LPDDR4)
#   ddr3 = same defconfig with LPDDR4 -> SUNXI_DRAM_H616_DDR3_1333
# Output per variant: u-boot-sunxi-with-spl.bin (+ u-boot.itb, bl31.bin).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/pins.env"

log() { printf 'build-uboot.sh: %s\n' "$*"; }
die() { printf 'build-uboot.sh: ERROR: %s\n' "$*" >&2; exit 1; }

USRC="" ASRC="" OUT="" VARIANT="both" JOBS="$(nproc 2>/dev/null || echo 4)" DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --uboot) USRC="$2"; shift 2 ;;
        --atf) ASRC="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --variant) VARIANT="$2"; shift 2 ;;
        --jobs) JOBS="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -n "$USRC" ] && [ -n "$ASRC" ] && [ -n "$OUT" ] \
    || die "need --uboot DIR --atf DIR --out DIR"
case "$VARIANT" in ddr3|ddr4|both) ;; *) die "bad --variant $VARIANT" ;; esac
EPOCH="${SOURCE_DATE_EPOCH:-$SOURCE_DATE_EPOCH_DEFAULT}"
export SOURCE_DATE_EPOCH="$EPOCH"
export CROSS_COMPILE="$KCROSS_COMPILE"

run() { if [ "$DRY" = 1 ]; then printf '+ %s\n' "$*"; else log "$*"; "$@"; fi; }
if [ "$DRY" = 1 ]; then
    [ -f "$USRC/Makefile" ] || log "dry-run: assuming u-boot tree at $USRC"
    [ -f "$ASRC/Makefile" ] || log "dry-run: assuming ATF tree at $ASRC"
else
    [ -f "$USRC/Makefile" ] || die "no u-boot tree at $USRC (run fetch.sh first)"
    [ -f "$ASRC/Makefile" ] || die "no ATF tree at $ASRC (run fetch.sh first)"
fi
command -v "${KCROSS_COMPILE}gcc" >/dev/null 2>&1 || [ "$DRY" = 1 ] \
    || die "missing cross compiler ${KCROSS_COMPILE}gcc (use build/docker image)"

# 1. ATF BL31 for sunxi H616/H700 (single build shared by both variants).
run make -C "$ASRC" -j"$JOBS" PLAT="$ATF_PLAT" DEBUG=0 bl31
BL31="$ASRC/build/$ATF_PLAT/release/bl31.bin"

# 2. U-Boot per DRAM variant (out-of-tree build dirs keep $USRC pristine).
build_variant() { # name extra-conf-fragment-or-empty
    local name="$1"
    local frag="$2"
    local obj="$OUT/obj-$name"
    run mkdir -p "$obj"
    run make -C "$USRC" O="$obj" "$UBOOT_DEFCONFIG"
    if [ -n "$frag" ]; then
        run bash -c "cat '$frag' >> '$obj/.config'"
        run make -C "$USRC" O="$obj" olddefconfig
    fi
    run make -C "$USRC" O="$obj" -j"$JOBS" BL31="$BL31"
    run mkdir -p "$OUT/$name"
    run cp "$obj/u-boot-sunxi-with-spl.bin" "$obj/u-boot.itb" "$OUT/$name/"
    run cp "$BL31" "$OUT/$name/bl31.bin"
    log "variant $name staged in $OUT/$name"
}

DDR3_FRAG="$HERE/config/uboot-rg35xx-h-ddr3-fragment.conf"
case "$VARIANT" in
    ddr4) build_variant ddr4 "" ;;
    ddr3) [ -f "$DDR3_FRAG" ] || die "missing $DDR3_FRAG"
          build_variant ddr3 "$DDR3_FRAG" ;;
    both) build_variant ddr4 ""
          [ -f "$DDR3_FRAG" ] || die "missing $DDR3_FRAG"
          build_variant ddr3 "$DDR3_FRAG" ;;
esac
run bash -c "cd '$OUT' && find ddr3 ddr4 -type f | sort | xargs sha256sum > SHA256SUMS.uboot"
log "u-boot staging ready in $OUT (epoch $EPOCH)"
