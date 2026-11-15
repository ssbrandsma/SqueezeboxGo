#!/usr/bin/env bash
# assemble-image.sh — reproducible RG35XX H SD image assembly (GPT, ddr3+ddr4).
#
# Usage:
#   assemble-image.sh --variant ddr3|ddr4 --uboot DIR --kernel DIR --rootfs DIR
#                     --out FILE [--size-mb N] [--epoch EPOCH]
#   assemble-image.sh --check-deps | --dry-run ... (same args, prints plan)
#
# Inputs: build-uboot.sh staging (DIR/<variant>/u-boot-sunxi-with-spl.bin),
# kernel staging (boot/Image, dtbs/*.dtb), rootfs staging (mkrootfs.sh output
# layered on the WP2 base). Runs unprivileged; filesystems are built in temp
# files and dd'd into place (no loop mounts, no root).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
DEV_DIR="$REPO_ROOT/platform/rg35xx-h"

log() { printf 'assemble-image.sh: %s\n' "$*"; }
die() { printf 'assemble-image.sh: ERROR: %s\n' "$*" >&2; exit 1; }

VARIANT="" UB="" KRN="" ROOTFS="" OUT="" SIZE_MB=2048 DRY=0
EPOCH="${SOURCE_DATE_EPOCH:-1794334272}"
while [ $# -gt 0 ]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --uboot) UB="$2"; shift 2 ;;
        --kernel) KRN="$2"; shift 2 ;;
        --rootfs) ROOTFS="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --size-mb) SIZE_MB="$2"; shift 2 ;;
        --epoch) EPOCH="$2"; shift 2 ;;
        --check-deps) CHECK_DEPS=1; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done

check_deps() { # returns 1 with a report when tools are missing
    local miss=0 t
    for t in python3 sfdisk mkfs.ext4 mkfs.vfat mcopy mkimage dd sha256sum fakeroot; do
        if command -v "$t" >/dev/null 2>&1; then log "tool OK: $t";
        else log "tool MISSING: $t"; miss=1; fi
    done
    [ "$miss" = 0 ] || log "hint: run inside the build/docker image for full tooling"
    return "$miss"
}
[ "${CHECK_DEPS:-0}" = 1 ] && { check_deps; exit "$?"; }

[ -n "$VARIANT" ] && [ -n "$UB" ] && [ -n "$KRN" ] && [ -n "$ROOTFS" ] && [ -n "$OUT" ] \
    || die "need --variant --uboot --kernel --rootfs --out"
case "$VARIANT" in ddr3|ddr4) ;; *) die "bad --variant $VARIANT" ;; esac

SPL="$UB/$VARIANT/u-boot-sunxi-with-spl.bin"
IMAGE_BIN="$KRN/boot/Image"
DTB="$KRN/dtbs/sun50i-h700-anbernic-rg35xx-h.dtb"
if [ "$DRY" = 1 ]; then
    [ -f "$SPL" ] || log "dry-run: assuming SPL blob at $SPL"
    [ -f "$IMAGE_BIN" ] || log "dry-run: assuming kernel at $IMAGE_BIN"
    [ -f "$DTB" ] || log "dry-run: assuming DTB at $DTB"
    [ -d "$ROOTFS/etc" ] || log "dry-run: assuming rootfs staging at $ROOTFS"
else
    [ -f "$SPL" ] || die "missing SPL blob $SPL (run build-uboot.sh --variant $VARIANT)"
    [ -f "$IMAGE_BIN" ] || die "missing kernel $IMAGE_BIN (run build-kernel.sh)"
    [ -f "$DTB" ] || die "missing DTB $DTB (run build-kernel.sh)"
    [ -d "$ROOTFS/etc" ] || die "missing rootfs staging $ROOTFS (run mkrootfs.sh)"
fi

BOOT_START=32768            # sectors; must match mksunxi_gpt.py/BOOT_START
BOOT_SECTORS=524288        # 256 MiB
ROOT_START=557056
SECTOR=512
export SOURCE_DATE_EPOCH="$EPOCH"

plan() { printf 'plan: %s\n' "$*"; }
if [ "$DRY" = 1 ]; then
    plan "variant=$VARIANT size=${SIZE_MB}MiB epoch=$EPOCH out=$OUT"
    plan "1. mksunxi_gpt.py --image OUT --size-mb $SIZE_MB"
    plan "2. dd SPL ($SPL) at sector 16"
    plan "3. boot.scr = mkimage -C none -A arm64 -T script $DEV_DIR/boot/boot.cmd"
    plan "4. mkfs.vfat 256M (label SQUEEZEBOOT, volid from epoch) + mcopy boot.scr Image dtb.img"
    plan "5. dd boot fs at sector $BOOT_START"
    plan "6. mkfs.ext4 -d ROOTFS -U fixed-uuid (label squeezebox-root) sized to root span"
    plan "7. dd root fs at sector $ROOT_START"
    plan "8. mksunxi_gpt.py --check + sha256sum -> OUT.sha256"
    exit 0
fi

check_deps || die "missing tools (see hint above)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. GPT skeleton.
python3 "$HERE/mksunxi_gpt.py" --image "$OUT" --size-mb "$SIZE_MB"
TOTAL_SECTORS=$((SIZE_MB * 1024 * 1024 / SECTOR))
ROOT_SECTORS=$((TOTAL_SECTORS - 33 - ROOT_START))

# 2. SPL blob at sector 16 (BROM load address); guard against blob overflow.
SPL_SECTORS=$(( ($(stat -c%s "$SPL") + SECTOR - 1) / SECTOR ))
[ $((16 + SPL_SECTORS)) -lt 4096 ] \
    || die "SPL blob too large ($SPL_SECTORS sectors, ends past array LBA 4096)"
dd if="$SPL" of="$OUT" bs=$SECTOR seek=16 conv=notrunc status=none
log "SPL written at sector 16 ($SPL_SECTORS sectors)"

# 3. boot.scr from source (never ship opaque binaries).
mkimage -C none -A arm64 -T script -d "$DEV_DIR/boot/boot.cmd" "$TMP/boot.scr" >/dev/null

# 4. FAT boot fs in a temp file, then dd into place.
BOOT_BYTES=$((BOOT_SECTORS * SECTOR))
VOLID=$(printf '%08X' $((EPOCH & 0xFFFFFFFF)))
truncate -s "$BOOT_BYTES" "$TMP/boot.vfat"
mkfs.vfat -F 32 -n SQUEEZEBOOT -i "$VOLID" "$TMP/boot.vfat" >/dev/null
mcopy -i "$TMP/boot.vfat" "$TMP/boot.scr" ::boot.scr
mcopy -i "$TMP/boot.vfat" "$IMAGE_BIN" ::Image
mcopy -i "$TMP/boot.vfat" "$DTB" ::dtb.img
log "boot fs: boot.scr Image dtb.img (volid $VOLID)"
dd if="$TMP/boot.vfat" of="$OUT" bs=$SECTOR seek=$BOOT_START conv=notrunc status=none

# 5. ext4 rootfs in a temp file (unprivileged: fixed UUID, root-owned, no dev nodes).
ROOT_BYTES=$((ROOT_SECTORS * SECTOR))
ROOT_UUID="0a1b2c3d-0002-4000-8000-000000000001"
truncate -s "$ROOT_BYTES" "$TMP/root.ext4"
# fakeroot: -d copies source ownership (builder uid) without it; the target
# rootfs must be root-owned. fakeroot also fakes device nodes if any appear.
# NOTE: mke2fs <=1.47.0 still stamps wall-clock + random journal UUID; see
# README "Known gap" (WP2: newer e2fsprogs or libfaketime in the container).
fakeroot mkfs.ext4 -q -L squeezebox-root -U "$ROOT_UUID" -d "$ROOTFS" \
    -E lazy_itable_init=0,root_owner=0:0 "$TMP/root.ext4" >/dev/null
dd if="$TMP/root.ext4" of="$OUT" bs=$SECTOR seek=$ROOT_START conv=notrunc status=none
log "root fs: ${ROOT_SECTORS} sectors (uuid $ROOT_UUID)"

# 6. Verify + manifest.
python3 "$HERE/mksunxi_gpt.py" --image "$OUT" --check
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")") | tee "$OUT.sha256"
log "image ready: $OUT ($VARIANT, epoch $EPOCH)"
