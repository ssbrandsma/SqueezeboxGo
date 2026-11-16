#!/bin/sh
# wifi.sh — Wi-Fi bring-up for RTL8821CS (installed to /usr/lib/squeezebox/).
# Usage: wifi.sh start|stop|status
# Uses wpa_supplicant + DHCP (udhcpc preferred, dhcpcd fallback). Reads
# /etc/squeezebox/system.conf (WIFI_IF, WIFI_ENABLED) and the live config
# /etc/wpa_supplicant/wpa_supplicant.conf, which is provisioned from
# /etc/squeezebox/wpa_supplicant.conf.template (never commit real PSKs).
set -eu

CONF="${SYSTEM_CONF:-/etc/squeezebox/system.conf}"
# shellcheck disable=SC1090 # CONF path intentionally overridable (SYSTEM_CONF)
[ -f "$CONF" ] && . "$CONF"
IFACE="${WIFI_IF:-wlan0}"
WPA_CONF="${WPA_CONF:-/etc/wpa_supplicant/wpa_supplicant.conf}"
PIDDIR="${PIDDIR:-/run/squeezebox}"

log() { printf 'wifi.sh: %s\n' "$*" >&2; }
LED_SH="$(dirname "$0")/led.sh"
led() { [ -x "$LED_SH" ] && "$LED_SH" "$@" || true; }
die() { log "ERROR: $*"; led fail "wifi: $*"; exit 1; }

dhcp_client() {
    if command -v udhcpc >/dev/null 2>&1; then echo udhcpc;
    elif command -v dhcpcd >/dev/null 2>&1; then echo dhcpcd;
    else echo none; fi
}

do_start() {
    led stage wifi
    [ "${WIFI_ENABLED:-1}" = "1" ] || die "disabled in $CONF"
    command -v wpa_supplicant >/dev/null 2>&1 || die "missing wpa_supplicant"
    [ -f "$WPA_CONF" ] || die "missing $WPA_CONF (provision from wpa_supplicant.conf.template)"
    [ -d "/sys/class/net/$IFACE" ] || die "no such interface $IFACE (driver/firmware?)"
    mkdir -p "$PIDDIR"
    ip link set "$IFACE" up
    wpa_supplicant -B -i "$IFACE" -c "$WPA_CONF" -P "$PIDDIR/wpa_supplicant.pid" \
        || die "wpa_supplicant failed"
    case "$(dhcp_client)" in
        udhcpc) udhcpc -i "$IFACE" -p "$PIDDIR/udhcpc.pid" -b -q || die "udhcpc failed" ;;
        dhcpcd) dhcpcd -4 "$IFACE" || die "dhcpcd failed" ;;
        none) die "no DHCP client (need udhcpc or dhcpcd)" ;;
    esac
    log "$IFACE up"
}

do_stop() {
    [ -f "$PIDDIR/udhcpc.pid" ] && kill "$(cat "$PIDDIR/udhcpc.pid")" 2>/dev/null || true
    [ -f "$PIDDIR/wpa_supplicant.pid" ] && kill "$(cat "$PIDDIR/wpa_supplicant.pid")" 2>/dev/null || true
    command -v dhcpcd >/dev/null 2>&1 && dhcpcd -k "$IFACE" 2>/dev/null || true
    ip link set "$IFACE" down 2>/dev/null || true
    log "$IFACE down"
}

do_status() {
    if [ -d "/sys/class/net/$IFACE" ] && ip -o link show "$IFACE" | grep -q 'state UP'; then
        ip -o -4 addr show "$IFACE" || true
    else
        log "$IFACE is down"; exit 1
    fi
}

case "${1:-}" in
    start) do_start ;;
    stop) do_stop ;;
    status) do_status ;;
    *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
