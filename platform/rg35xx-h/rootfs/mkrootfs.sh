#!/usr/bin/env bash
# mkrootfs.sh — assemble the rootfs staging tree (skeleton + overlay + services).
#
# Usage:
#   mkrootfs.sh --staging DIR [--with-services] [--with-config] [--epoch EPOCH]
#
# Runs unprivileged; /dev stays empty (devtmpfs at boot). Writes DIR/manifest
# (path, mode, sha256) so rebuilds are diffable. The base userland is NOT
# built here — stage stage-userland.sh (debootstrap minbase) under DIR first,
# then this script layers the Squeezebox tree on top (idempotent). Without a
# base userland the tree still stages (skeleton + payload) but cannot boot to
# userspace; the script says so loudly (see the userland check below).
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
    for s in squeezeplay.sh splash.sh wifi.sh firstboot.sh led.sh; do
        [ -f "$DEV/services/$s" ] || die "missing services/$s"
        install -m 0755 "$DEV/services/$s" "$STAGING/usr/lib/squeezebox/$s"
    done
    for u in splash.service wifi.service squeezeplay.service squeezebox-firstboot.service; do
        [ -f "$DEV/services/systemd/$u" ] || die "missing services/systemd/$u"
        install -m 0644 "$DEV/services/systemd/$u" \
            "$STAGING/usr/lib/systemd/system/$u"
    done
    # enable: splash+wifi+squeezeplay+firstboot in multi-user.target.wants
    mkdir -p "$STAGING/etc/systemd/system/multi-user.target.wants"
    for u in splash.service wifi.service squeezeplay.service squeezebox-firstboot.service; do
        ln -sf "/usr/lib/systemd/system/$u" \
            "$STAGING/etc/systemd/system/multi-user.target.wants/$u"
    done
    log "services installed + enabled"
fi

# 3b. Base-userland wiring (consoles, ssh, time, audio state). Each link is
# created only when the target unit file exists in the staging tree, so
# skeleton-only staging (no userland yet) stays link-clean. This mirrors what
# `systemctl enable` would record, parsed from each unit's [Install] section.
enable_unit() { # $1 = unit name (e.g. ssh.service, getty@tty1.service)
    local unit="$1" tmpl target=""
    # Template instances (serial-getty@ttyS0) resolve to their @.service file.
    case "$unit" in
        *@*.*) tmpl="${unit%%@*}@.${unit##*.}" ;;
        *) tmpl="$unit" ;;
    esac
    if [ -f "$STAGING/usr/lib/systemd/system/$tmpl" ]; then
        target="/usr/lib/systemd/system/$tmpl"
    elif [ -f "$STAGING/lib/systemd/system/$tmpl" ]; then
        target="/lib/systemd/system/$tmpl"
    elif [ -f "$STAGING/etc/systemd/system/$tmpl" ]; then
        target="/etc/systemd/system/$tmpl"
    else
        log "wiring: $unit skipped (no $tmpl in staging)"
        return 0
    fi
    local want
    want="$(sed -n '/^\[Install\]/,/^\[/p' "$STAGING$target" \
        | grep '^WantedBy=' | head -1 | cut -d= -f2 | tr ' ' '\n' | head -1 || true)"
    [ -n "$want" ] || { log "wiring: $unit has no WantedBy, skipped"; return 0; }
    mkdir -p "$STAGING/etc/systemd/system/$want.wants"
    ln -sf "$target" "$STAGING/etc/systemd/system/$want.wants/$unit"
    log "wiring: $unit enabled in $want.wants"
}
if [ "$WITH_SVC" = 1 ]; then
    if [ -e "$STAGING/sbin/init" ] || [ -e "$STAGING/usr/lib/systemd/systemd" ]; then
        log "base userland present (init found)"
    else
        log "WARNING: no base userland in $STAGING (run stage-userland.sh first);"
        log "WARNING: this tree stages but CANNOT boot to userspace (no init/systemd)."
        log "WARNING: docker hosts can use: stage-userland.sh --userland container"
    fi
    # UART console (matches console=ttyS0 in boot/boot.cmd) + framebuffer console.
    enable_unit "serial-getty@ttyS0.service"
    enable_unit "getty@tty1.service"
    # ssh (host keys are generated by squeezebox-firstboot.service on 1st boot).
    enable_unit "ssh.service"
    # clock sync.
    enable_unit "systemd-timesyncd.service"
    # ALSA mixer restore/persist needs no wiring: alsa-utils ships
    # sound.target.wants/{alsa-restore,alsa-state}.service in the deb
    # (verified in staging).
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
# Manifests are written after the clamp above; pin their own mtimes too so
# every staging inode is epoch-stable (content already excludes manifest.*).
if [ "$EPOCH" != "0" ]; then
    touch -h -d "@$EPOCH" "$STAGING/manifest.modes" "$STAGING/manifest.sha256"
fi
log "staging ready: $STAGING ($(wc -l < "$STAGING/manifest.sha256") files)"
