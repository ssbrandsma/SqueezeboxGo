#!/usr/bin/env bash
# mkrootfs.sh — assemble the rootfs staging tree (skeleton + overlay + services).
#
# Usage:
#   mkrootfs.sh --staging DIR [--with-services] [--with-config] [--epoch EPOCH]
#
# Runs unprivileged; /dev stays empty (devtmpfs at boot). Writes DIR/manifest
# (path, mode, sha256) so rebuilds are diffable. The base userland
# (glibc/busybox/coreutils/systemd) is NOT built here — WP2 mounts the
# chosen base (debootstrap/buildroot, see README) under DIR first, then this
# script layers the Squeezebox tree on top (idempotent).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV="$(cd "$HERE/.." && pwd)"

log() { printf 'mkrootfs.sh: %s\n' "$*"; }
die() { printf 'mkrootfs.sh: ERROR: %s\n' "$*" >&2; exit 1; }

STAGING="" WITH_SVC=0 WITH_CONF=0 EPOCH="${SOURCE_DATE_EPOCH:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --staging) STAGING="$2"; shift 2 ;;
        --with-services) WITH_SVC=1; shift ;;
        --with-config) WITH_CONF=1; shift ;;
        --epoch) EPOCH="$2"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) die "unknown arg: $1" ;;
    esac
done
[ -n "$STAGING" ] || die "need --staging DIR"
mkdir -p "$STAGING"

# 1. Skeleton dirs.
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2086
    set -- $line
    [ "$1" = "d" ] || die "bad skeleton line: $line"
    mkdir -p "$STAGING$2"
    chmod "$3" "$STAGING$2"
done < "$HERE/skeleton.list"
log "skeleton created"

# 2. Static overlay (rootfs/overlay/<path> -> staging/<path>).
if [ -d "$HERE/overlay" ]; then
    (cd "$HERE/overlay" && find . -type f | sort) | while IFS= read -r f; do
        dest="$STAGING/${f#./}"
        mkdir -p "$(dirname "$dest")"
        install -m 0644 "$HERE/overlay/$f" "$dest"
    done
    # sensitive files keep their repo modes:
    [ -f "$HERE/overlay/etc/shadow" ] && chmod 0000 "$STAGING/etc/shadow" || true
    log "overlay installed"
fi

# 3. Service scripts -> /usr/lib/squeezebox (executable).
if [ "$WITH_SVC" = 1 ]; then
    for s in squeezeplay.sh splash.sh wifi.sh; do
        [ -f "$DEV/services/$s" ] || die "missing services/$s"
        install -m 0755 "$DEV/services/$s" "$STAGING/usr/lib/squeezebox/$s"
    done
    for u in splash.service wifi.service squeezeplay.service; do
        [ -f "$DEV/services/systemd/$u" ] || die "missing services/systemd/$u"
        install -m 0644 "$DEV/services/systemd/$u" \
            "$STAGING/usr/lib/systemd/system/$u"
    done
    # enable: splash+wifi+squeezeplay in multi-user.target.wants
    mkdir -p "$STAGING/etc/systemd/system/multi-user.target.wants"
    for u in splash.service wifi.service squeezeplay.service; do
        ln -sf "/usr/lib/systemd/system/$u" \
            "$STAGING/etc/systemd/system/multi-user.target.wants/$u"
    done
    log "services installed + enabled"
fi

# 4. Configuration templates -> /etc/squeezebox (NOT active secrets).
if [ "$WITH_CONF" = 1 ]; then
    install -m 0644 "$DEV/configuration/system.conf" \
        "$STAGING/etc/squeezebox/system.conf"
    install -m 0600 "$DEV/configuration/wpa_supplicant.conf.template" \
        "$STAGING/etc/squeezebox/wpa_supplicant.conf.template"
    install -m 0644 "$DEV/configuration/sshd-10-squeezebox.conf" \
        "$STAGING/etc/ssh/sshd_config.d/10-squeezebox.conf"
    log "configuration installed"
fi

# 5. Reproducibility: ALL mtimes to epoch when given (checkout times vary),
# then manifest. Unconditional: clamping only newer files would still embed
# the checker's clock for older files.
if [ "$EPOCH" != "0" ]; then
    find "$STAGING" -exec touch -h -d "@$EPOCH" {} +
    log "mtimes set to $EPOCH"
fi
# Both manifests exclude manifest.* so re-runs are idempotent. They ship inside
# the image at /manifest.* for on-device verification.
(cd "$STAGING" && find . -mindepth 1 ! -name 'manifest.*' -printf '%M %p\n' | sort > manifest.modes)
(cd "$STAGING" && find . -type f ! -name 'manifest.*' | sort | xargs sha256sum > manifest.sha256)
log "staging ready: $STAGING ($(wc -l < "$STAGING/manifest.sha256") files)"
