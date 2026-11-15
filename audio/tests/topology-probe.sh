#!/bin/sh
# topology-probe.sh — ALSA topology test (WP1)
#
# Verifies the expected RG35XX H sound topology: internal H616 codec card
# present at the pinned index with a playback PCM, no capture PCM on it,
# and (optionally) a USB DAC card. Runs live against /proc/asound, or
# against fixtures with PROC_ASOUND=<dir> (host validation).
#
# Output: TAP. Exit 0 iff all assertions pass.
#
# Usage: topology-probe.sh [--proc-asound DIR] [--expect-usb 0|1]

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PROC_ASOUND="${PROC_ASOUND:-/proc/asound}"
EXPECT_USB=0

while [ $# -gt 0 ]; do
    case "$1" in
        --proc-asound) PROC_ASOUND="$2"; shift 2 ;;
        --expect-usb) EXPECT_USB="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

DETECT="$HERE/../alsa/capability-detect.sh"
n=0; failed=0
ok()   { n=$((n+1)); echo "ok $n - $1"; }
nok()  { n=$((n+1)); failed=$((failed+1)); echo "not ok $n - $1"; [ -n "${2:-}" ] && echo "  $2"; }
skip() { n=$((n+1)); echo "ok $n - $1 # SKIP $2"; }

out="$(PROC_ASOUND="$PROC_ASOUND" SYS_ROOT="${SYS_ROOT:-/sys}" sh "$DETECT" --quiet 2>/dev/null)" \
    || { nok "capability-detect runs" "exit=$?"; echo "1..$n"; exit 1; }
ok "capability-detect runs"

val() { printf '%s' "$out" | sed -n "s/^$1=//p" | head -1; }

count="$(val 'card\.count')"
case "$count" in ''|*[!0-9]*) nok "card.count is numeric" "got '$count'"; count=0 ;;
                         *) ok "card.count is numeric ($count)" ;; esac

internal="$(val 'internal\.card')"
if [ "$internal" = "-1" ] || [ -z "$internal" ]; then
    nok "internal H616 codec card present"
else
    ok "internal H616 codec card present (index $internal)"
    info="$PROC_ASOUND/card$internal/pcm0p/info"
    if [ -r "$info" ]; then
        ok "internal card has playback PCM pcm0p"
        avail="$(sed -n 's/^subdevices_avail: *//p' "$info" | head -1)"
        [ "$avail" -ge 1 ] 2>/dev/null && ok "playback subdevice available (avail=$avail)" \
            || nok "playback subdevice available" "avail='$avail' (device busy or missing)"
    else
        nok "internal card has playback PCM pcm0p" "$info unreadable"
    fi
    if [ -e "$PROC_ASOUND/card$internal/pcm0c" ]; then
        nok "internal card has no capture PCM (H616 link is playback_only)"
    else
        ok "internal card has no capture PCM (H616 link is playback_only)"
    fi

    # --- sun4i-codec specifics (H616/H700 analog codec) ------------------
    # Identity fields come from the /proc/asound/cards line via
    # capability-detect; PCM details from pcm0p/info. Find our slot.
    slot=""
    i=0
    while [ "$i" -lt "$count" ]; do
        [ "$(val "card\\.$i\\.index")" = "$internal" ] && slot="$i"
        i=$((i+1))
    done
    if [ -z "$slot" ]; then
        nok "internal card slot lookup in capability-detect output"
    else
        ok "internal card slot lookup in capability-detect output"
        cid="$(val "card\\.$slot\\.id")"
        cdrv="$(val "card\\.$slot\\.driver")"
        cusb="$(val "card\\.$slot\\.usb")"
        [ "$cid" = "H616AudioCodec" ] \
            && ok "internal card id is H616AudioCodec" \
            || nok "internal card id is H616AudioCodec" "got '$cid'"
        case "$cdrv" in
            *H616*|*sun4i*|*sunxi*)
                ok "internal card driver is sun4i-codec family ($cdrv)" ;;
            *) nok "internal card driver is sun4i-codec family" "got '$cdrv'" ;;
        esac
        [ "$cusb" = "0" ] \
            && ok "internal card is not a USB card" \
            || nok "internal card is not a USB card" "usb='$cusb'"
        case "$cdrv" in
            *oopback*) nok "internal card is not snd-aloop" "got '$cdrv'" ;;
            *) ok "internal card is not snd-aloop" ;;
        esac
        if [ -r "$info" ]; then
            pid="$(sed -n 's/^id: *//p' "$info" | head -1)"
            pname="$(sed -n 's/^name: *//p' "$info" | head -1)"
            subcnt="$(sed -n 's/^subdevices_count: *//p' "$info" | head -1)"
            [ "$pid" = "CDC PCM" ] \
                && ok "internal pcm0p id is CDC PCM" \
                || nok "internal pcm0p id is CDC PCM" "got '$pid'"
            [ "$pname" = "CDC PCM" ] \
                && ok "internal pcm0p name is CDC PCM" \
                || nok "internal pcm0p name is CDC PCM" "got '$pname'"
            [ "$subcnt" = "1" ] \
                && ok "internal pcm0p has exactly 1 subdevice (single holder)" \
                || nok "internal pcm0p has exactly 1 subdevice" "got '$subcnt'"
        fi
        # ASoC codec cards have no USB altsetting table; its presence
        # would mean capability-detect matched the wrong card.
        if [ -e "$PROC_ASOUND/card$internal/stream0" ]; then
            nok "internal card has no USB-style stream0"
        else
            ok "internal card has no USB-style stream0"
        fi
        # SPDIF is a kernel module (see config cross-check below), not
        # loaded in the base image: no second playback device expected.
        if [ -e "$PROC_ASOUND/card$internal/pcm1p" ]; then
            nok "internal card has no pcm1p (SPDIF module not loaded)"
        else
            ok "internal card has no pcm1p (SPDIF module not loaded)"
        fi
    fi
fi

usb="$(val 'usb\.card')"
if [ "$EXPECT_USB" -eq 1 ]; then
    if [ "$usb" = "-1" ] || [ -z "$usb" ]; then
        nok "USB DAC card present (expected)"
    else
        ok "USB DAC card present (index $usb)"
    fi
else
    if [ "$usb" = "-1" ] || [ -z "$usb" ]; then
        skip "USB DAC card present" "no USB DAC attached (EXPECT_USB=0)"
    else
        ok "USB DAC card present (index $usb)"
    fi
fi

# USB DAC specifics (when a DAC is resolved, expected or not).
if [ -n "$usb" ] && [ "$usb" != "-1" ]; then
    usbid="$PROC_ASOUND/card$usb/usbid"
    if [ -r "$usbid" ]; then
        vid="$(tr -d ' \t\n' < "$usbid" 2>/dev/null)"
        case "$vid" in
            ????[:]????)
                ok "USB card usbid parses as VID:PID ($vid)" ;;
            *) nok "USB card usbid parses as VID:PID" "got '$vid'" ;;
        esac
    else
        nok "USB card usbid file present" "$usbid unreadable"
    fi
    ustream="$PROC_ASOUND/card$usb/stream0"
    if [ -r "$ustream" ]; then
        grep -q 'Rates: ' "$ustream" 2>/dev/null \
            && ok "USB card stream0 lists altsetting rates" \
            || nok "USB card stream0 lists altsetting rates"
    else
        skip "USB card stream0 rates" "$ustream unreadable"
    fi
fi

# --- platform kernel config cross-check ----------------------------------
# Grounds the topology expectations in the pinned kernel fragment: the
# sun4i-codec drivers are built-in (=y, internal card always present),
# USB audio / SPDIF / loopback are modules (=m, optional or absent).
KCONF="$HERE/../../platform/rg35xx-h/kernel/config/linux-rg35xx-h-aarch64.conf"
if [ -r "$KCONF" ]; then
    kopt() { grep -E "^$1=" "$KCONF" 2>/dev/null | tail -1; }
    kline="$(kopt 'CONFIG_SND_SUN8I_CODEC')"
    [ "$kline" = "CONFIG_SND_SUN8I_CODEC=y" ] \
        && ok "kconf: CONFIG_SND_SUN8I_CODEC=y (internal card always present)" \
        || nok "kconf: CONFIG_SND_SUN8I_CODEC=y" "got '$kline'"
    kline="$(kopt 'CONFIG_SND_SUN50I_CODEC_ANALOG')"
    [ "$kline" = "CONFIG_SND_SUN50I_CODEC_ANALOG=y" ] \
        && ok "kconf: CONFIG_SND_SUN50I_CODEC_ANALOG=y (LINEOUT path)" \
        || nok "kconf: CONFIG_SND_SUN50I_CODEC_ANALOG=y" "got '$kline'"
    kline="$(kopt 'CONFIG_SND_USB_AUDIO')"
    case "$kline" in
        "CONFIG_SND_USB_AUDIO=m"|"CONFIG_SND_USB_AUDIO=y")
            ok "kconf: $kline (USB DAC supported)" ;;
        *) nok "kconf: CONFIG_SND_USB_AUDIO=m|y" "got '$kline'" ;;
    esac
    kline="$(kopt 'CONFIG_SND_SUN4I_SPDIF')"
    [ "$kline" != "CONFIG_SND_SUN4I_SPDIF=y" ] \
        && ok "kconf: SPDIF not built-in ($kline; no pcm1p expected)" \
        || nok "kconf: SPDIF not built-in" "got '$kline'"
    kline="$(kopt 'CONFIG_SND_ALOOP')"
    [ "$kline" != "CONFIG_SND_ALOOP=y" ] \
        && ok "kconf: snd-aloop not built-in ($kline; cannot shadow internal)" \
        || nok "kconf: snd-aloop not built-in" "got '$kline'"
else
    skip "kernel config cross-check" "$KCONF unreadable"
fi

# Mixer controls on the internal card (live only: needs amixer).
if [ -n "$internal" ] && [ "$internal" != "-1" ] && command -v amixer >/dev/null 2>&1; then
    ctrls="$(amixer -c "$internal" scontents 2>/dev/null | grep -E '^Simple mixer control' || true)"
    for want in "DAC Playback Volume" "Line Out Playback Volume" \
                "Line Out Playback Switch" "Speaker Playback Switch"; do
        printf '%s' "$ctrls" | grep -qF "'$want'" \
            && ok "mixer control present: $want" \
            || nok "mixer control present: $want"
    done
else
    skip "mixer controls enumerated" "needs live amixer + internal card"
fi

echo "1..$n"
[ "$failed" -eq 0 ]
